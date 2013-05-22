SO-Tema5
=========

Operating Systems Homework

Asynchronous web server



Contributors:
* Diana Mincu - 331CB
* Andreea Bejgu - 331CB

Andreea Bejgu
=============

Diana Mincu
===========

I set up the initial project (the repo on github, Makefiles, and so on) and parsed the incoming requests as in the parser use example. We started the homework on the echo_reponse example and I modified the listening port to AWS_LISTEN_PORT. Also I wrote the handle_client_request function in which we initialize the parser, find the path to the file and fill in the buffers for writing the response to the request. We check for the existance of the file with the open function (seeing as we also need a file descriptor later on).

So if open return with -1 then the send buffer in the connection conn is set to "HTTP/1.0 404 Not found\r\n\r\n". When I used only "HTTP/1.0 404 Not found" (so without the "\r\n\r\n" I found that the tests which compare the files would fail, even though the files would get successfully transffered. On the other hand, if open returns with no error code than the send buffer is filled in with "HTTP/1.0 200 OK\r\n\r\n".

I also wrote the part for the zero-copying file sending (the static files). In the send_message function, after we send the message with either 404 or 200 codes, if the file opened (the path was correct) and the path contained the keyword static, then we use sendfile to send the file to the user. A problem that I encountered was that I did not close the connection after the transfer was complete, which caused the client to not receive messages from time to time, and therefore the checker got stuck at test 15. After I fixed this problem, the tests would regularly pass.
