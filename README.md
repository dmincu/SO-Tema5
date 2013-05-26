SO-Tema5
=========

Operating Systems Homework

Asynchronous web server



Contributors:
* Diana Mincu - 331CB
* Andreea Bejgu - 331CB

Andreea Bejgu
=============

I worked on the asynchronous file sending. I added the necessary fields in the structure we used for each connection (iocb structures, event descriptor, number of transfers) and I tried diferent solutions. First I tried to initialize all the iocb structures for reading from the file and to transfer each piece of size BUFSIZ into a buffer which eventually would contain the whole file. Then after receiving the file I would send it part by part on the socket, but this solution wasn't efficient and didn't serve the purpose.

Then I tried to add the event for the connection in the epollfd set of descriptors on which I was waiting for a notification. When a notification arrived on that eventfd, I would check to see how many AIO finished and tried to send on the socket as many parts as I could. After the whole file was sent, the connection closed (the send_message function returned before closing the connection, if the parameter dynamic was found).

Eventually we combined the solutions and tried to send the file piece-by-piece; when a AIO read operation finished we started an AIO write one  (sending on the socket).



Diana Mincu
===========

I set up the initial project (the repo on github, Makefiles, and so on) and parsed the incoming requests as in the parser use example. We started the homework on the echo_reponse example and I modified the listening port to AWS_LISTEN_PORT. Also I wrote the handle_client_request function in which we initialize the parser, find the path to the file and fill in the buffers for writing the response to the request. We check for the existance of the file with the open function (seeing as we also need a file descriptor later on).

So if open returns with -1 then the send buffer in the connection conn is set to "HTTP/1.0 404 Not found\r\n\r\n". When I used only "HTTP/1.0 404 Not found" (so without the "\r\n\r\n" I found that the tests which compare the files would fail, even though the files would get successfully transffered). On the other hand, if open returns with no error code then the send buffer is filled in with "HTTP/1.0 200 OK\r\n\r\n".

I also wrote the part for the zero-copying file sending (the static files). In the send_message function, after we send the message with either 404 or 200 codes, if the file opened (the path was correct) and the path contained the keyword static, then we use sendfile to send the file to the user. A problem that I encountered was that I did not close the connection after the transfer was complete, which caused the client to not receive messages from time to time, and therefore the checker got stuck at test 15. After I fixed this problem, the tests would regularly pass.

I looked into the asynchronous file sending. We based our approach on the 11th laboratory, exercise 4 kaio.c. We have two functions prep_io_read_from_file, prep_io_write_to_socket. In each we initialize the iocb structures. We use io_prep_pread and io_prep_pwrite for initializing the buffer and writing from it, io_setup and io_context_destroy to intitialize and destroy the context and io_submit and io_getevents to start and wait for the reading/writing to finish.
