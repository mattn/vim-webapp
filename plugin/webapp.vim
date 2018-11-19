function! s:start() abort
  let s:ch = ch_listen("127.0.0.1:8888", {"callback": function("webapp#accept")})
endfunction

command WebServer call s:start()
