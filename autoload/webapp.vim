let s:basedir = get(g:, 'webapp_static_dir', expand('<sfile>:h:h') . '/static')

let s:mimetypes = {
\ 'ico':  'image/x-icon',
\ 'html': 'text/html; charset=UTF-8',
\ 'js':   'application/javascript; charset=UTF-8',
\ 'txt':  'text/plain; charset=UTF-8',
\ 'css':  'text/css; charset=UTF-8',
\ 'jpg':  'image/jpeg',
\ 'gif':  'image/gif',
\ 'png':  'image/png',
\}

let s:statustexts = {
\ "100": "Continue",
\ "101": "Switching Protocols",
\ "102": "Processing",
\ "200": "OK",
\ "201": "Created",
\ "202": "Accepted",
\ "203": "Non-Authoritative Information",
\ "204": "No Content",
\ "205": "Reset Content",
\ "206": "Partial Content",
\ "207": "Multi-Status",
\ "208": "Already Reported",
\ "226": "IM Used",
\ "300": "Multiple Choices",
\ "301": "Moved Permanently",
\ "302": "Found",
\ "303": "See Other",
\ "304": "Not Modified",
\ "305": "Use Proxy",
\ "307": "Temporary Redirect",
\ "308": "Permanent Redirect",
\ "400": "Bad Request",
\ "401": "Unauthorized",
\ "402": "Payment Required",
\ "403": "Forbidden",
\ "404": "Not Found",
\ "405": "Method Not Allowed",
\ "406": "Not Acceptable",
\ "407": "Proxy Authentication Required",
\ "408": "Request Timeout",
\ "409": "Conflict",
\ "410": "Gone",
\ "411": "Length Required",
\ "412": "Precondition Failed",
\ "413": "Request Entity Too Large",
\ "414": "Request URI Too Long",
\ "415": "Unsupported Media Type",
\ "416": "Requested Range Not Satisfiable",
\ "417": "Expectation Failed",
\ "418": "I'm a teapot",
\ "421": "Misdirected Request",
\ "422": "Unprocessable Entity",
\ "423": "Locked",
\ "424": "Failed Dependency",
\ "426": "Upgrade Required",
\ "428": "Precondition Required",
\ "429": "Too Many Requests",
\ "431": "Request Header Fields Too Large",
\ "451": "Unavailable For Legal Reasons",
\ "500": "Internal Server Error",
\ "501": "Not Implemented",
\ "502": "Bad Gateway",
\ "503": "Service Unavailable",
\ "504": "Gateway Timeout",
\ "505": "HTTP Version Not Supported",
\ "506": "Variant Also Negotiates",
\ "507": "Insufficient Storage",
\ "508": "Loop Detected",
\ "510": "Not Extended",
\ "511": "Network Authentication Required",
\}

function! webapp#path2slash(path) abort
  return substitute(a:path, '\\', '/', 'g')
endfunction

function! webapp#fname2mimetype(fname) abort
  let ext = fnamemodify(a:fname, ':e')
  if has_key(s:mimetypes, ext)
    return s:mimetypes[ext]
  else
    return 'application/octet-stream'
  endif
endfunction

if !exists('s:handlers')
  let s:handlers = {}
endif

function! webapp#form_params(req) abort
  let params = {}
  for q in split(a:req.body, '&') 
    let pos = stridx(q, '=')
    if pos > 0
      let params[q[:pos-1]] = q[pos+1:]
    endif
  endfor
  return params
endfunction

function! webapp#params(req) abort
  let params = {}
  for q in split(a:req.query, '&') 
    let pos = stridx(q, '=')
    if pos > 0
      let params[q[:pos-1]] = q[pos+1:]
    endif
  endfor
  return params
endfunction

function! webapp#handle(path, Func) abort
  let s:handlers[a:path] = a:Func
endfunction

function! webapp#json(req, obj, ...) abort
  let res = json_encode(a:obj)
  let cb = get(a:000, 0, '')
  if len(cb) != 0
    let res = cb . '(' . res . ')'
  endif
  return {"header": ["Content-Type: application/json; charset=UTF-8"], "body": res}
endfunction

function! webapp#redirect(req, to) abort
  return {"header": ["Location: " . a:to], "status": 302}
endfunction

function! webapp#servefile(req, basedir) abort
  let res = {"header": [], "body": "", "status": 200}
  let fname = a:basedir . a:req.path
  if isdirectory(fname)
    let fname .= '/index.html'
  endif
  if filereadable(fname)
    let mimetype = webapp#fname2mimetype(fname)
    call add(res.header, "Content-Type: " . mimetype)
    if exists('v:t_blob')
      let res.body = readfile(fname, 'B')
    else
      if mimetype =~ '^text/'
        let res.body = iconv(join(readfile(fname, 'b'), "\n"), "UTF-8", &encoding)
      else
        let res.body = map(split(substitute(system("xxd -ps " . fname), "[\r\n]", "", "g"), '..\zs'), '"0x".v:val+0')
      endif
    endif
  else
    let res.status = 404
    let res.body = "Not Found"
    "call add(res.header, "Content-Type: text/plain; charset=UTF-8")
    "let res.body = join(map(map(split(glob(fname . '/*'), "\n"), 'a:req.path . webapp#path2slash(v:val[len(fname):])'), '"<a href=\"".webapi#http#encodeURIComponent(v:val)."\">".webapi#html#encodeEntityReference(v:val)."</a><br>"'), "\n")
  endif
  return res
endfunction

function! webapp#serve(req, ...) abort
  try
    let basedir = get(empty(a:000) ? {'basedir': s:basedir} : a:000[0], 'basedir', s:basedir)
    for path in reverse(sort(keys(s:handlers)))
      if stridx(a:req.path, path) == 0
        return s:handlers[path](a:req)
      endif
    endfor
    let res = webapp#servefile(a:req, basedir)
  catch
    let res = {"header": ['Content-Type: text/plain; charset=UTF-8'], "body": "Internal Server Error: " . v:exception, "status": 500}
  endtry
  return res
endfunction

function! webapp#accept(ch, b) abort
  call ch_setoptions(a:ch, {'mode': 'raw'})
  let req = { 'header': [] }
  let content = ch_readraw(a:ch)
  let pos = stridx(content, "\n")
  if pos == -1
    call ch_close(a:ch)
    return
  endif
  let tok = split(content[:pos], '\s\+')
  if len(tok) < 2
    call ch_close(a:ch)
    return
  endif
  let content = content[pos+1:]
  let req['method'] = tok[0]
  let pos = stridx(tok[1], "?")
  let req['path'] = pos != -1 ? tok[1][:pos] : tok[1]
  let req['query'] = pos != -1 ? tok[1][pos+1:] : tok[1]

  let pos = stridx(content, "\r\n\r\n")
  if pos != -1
    let header = content[:pos]
    let body = content[pos+4:]
  else
    let pos = stridx(content, "\n\n")
    if pos != -1
      let header = content[:pos]
      let body = content[pos+2:]
    else
      let header = content
      let body = ''
    endif
  endif
  let req.header = split(header, '\r\?\n')
  let req.body = body
  let status = 0
  try
    let res = webapp#serve(req)
  catch
    let res = {'status': 500}
  endtry
  let status = get(res, 'status', 200)
  let header = get(res, 'header', [])
  call insert(header, printf('HTTP/1.0 %d %s', status, s:statustexts[status]))
  call ch_sendraw(a:ch, join(header, "\n") . "\n\n")
  call ch_sendraw(a:ch, get(res, 'body', ''))
  call ch_close(a:ch)
endfunction
