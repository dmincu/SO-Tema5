#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#include <sys/types.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/epoll.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/sendfile.h>
#include <libaio.h>
#include <sys/eventfd.h>

#include "../headers/util.h"
#include "../headers/debug.h"
#include "../headers/sock_util.h"
#include "../headers/w_epoll.h"
#include "../headers/aws.h"

#include "http-parser/http_parser.h"

#define NUM_OPS 10

/* parser used for requests */
static http_parser request_parser;

/* storage for request_path */
static char request_path[BUFSIZ];

/* server socket file descriptor */
static int listenfd;

/* epoll file descriptor */
static int epollfd;

enum connection_state {
	STATE_DATA_RECEIVED,
	STATE_DATA_SENT,
	STATE_CONNECTION_CLOSED
};

/* structure acting as a connection handler */
struct connection {
	int sockfd;
	int fd;
	char pathname[BUFSIZ];

	/* buffers used for receiving messages and then echoing them back */
	char recv_buffer[BUFSIZ];
	size_t recv_len;
	char send_buffer[BUFSIZ];
	size_t send_len;
	enum connection_state state;

	struct iocb *iocb;
	struct iocb **piocb;
	int iocbs;
	int efd;
};

char buffer[BUFSIZ];

int eefd;

/*
 * Callback is invoked by HTTP request parser when parsing request path.
 * Request path is stored in global request_path variable.
 */
static int on_path_cb(http_parser *p, const char *buf, size_t len)
{
	assert(p == &request_parser);
	memcpy(request_path, buf, len);

	return 0;
}

/* Use mostly null settings except for on_path callback. */
static http_parser_settings settings_on_path = {
	/* on_message_begin */ 0,
	/* on_header_field */ 0,
	/* on_header_value */ 0,
	/* on_path */ on_path_cb,
	/* on_url */ 0,
	/* on_fragment */ 0,
	/* on_query_string */ 0,
	/* on_body */ 0,
	/* on_headers_complete */ 0,
	/* on_message_complete */ 0
};

/*
 * Initialize connection structure on given socket.
 */
static struct connection *connection_create(int sockfd)
{
	struct connection *conn = malloc(sizeof(*conn));
	DIE(conn == NULL, "malloc");

	conn->sockfd = sockfd;
	memset(conn->recv_buffer, 0, BUFSIZ);
	memset(conn->send_buffer, 0, BUFSIZ);

	return conn;
}

/*
 * Remove connection handler.
 */

static void connection_remove(struct connection *conn)
{
	if (conn->fd > 0)
		close(conn->fd);
	close(conn->sockfd);
	conn->state = STATE_CONNECTION_CLOSED;
	free(conn);
}

/*
 * Handle a new connection request on the server socket.
 */

static void handle_new_connection(void)
{
	static int sockfd;
	socklen_t addrlen = sizeof(struct sockaddr_in);
	struct sockaddr_in addr;
	struct connection *conn;
	int rc;

	/* accept new connection */
	sockfd = accept(listenfd, (SSA *) &addr, &addrlen);
	DIE(sockfd < 0, "accept");

	dlog(LOG_ERR, "Accepted connection from: %s:%d\n", inet_ntoa(addr.sin_addr), ntohs(addr.sin_port));

	fcntl(sockfd, F_SETFL, O_NONBLOCK);

	/* instantiate new connection handler */
	conn = connection_create(sockfd);

	/* add socket to epoll */
	rc = w_epoll_add_ptr_in(epollfd, sockfd, conn);
	DIE(rc < 0, "w_epoll_add_in");
}

/*
 * Receive message on socket.
 * Store message in recv_buffer in struct connection.
 */

static enum connection_state receive_message(struct connection *conn)
{
	ssize_t bytes_recv;
	int rc;
	char abuffer[64];

	rc = get_peer_address(conn->sockfd, abuffer, 64);
	if (rc < 0) {
		ERR("get_peer_address");
		goto remove_connection;
	}

	bytes_recv = recv(conn->sockfd, conn->recv_buffer, BUFSIZ, 0);
	if (bytes_recv < 0) {		/* error in communication */
		dlog(LOG_ERR, "Error in communication from: %s\n", abuffer);
		goto remove_connection;
	}
	if (bytes_recv == 0) {		/* connection closed */
		dlog(LOG_INFO, "Connection closed from: %s\n", abuffer);
		goto remove_connection;
	}

	dlog(LOG_DEBUG, "Received message from: %s\n", abuffer);

	printf("--\n%s--\n", conn->recv_buffer);

	conn->recv_len = bytes_recv;
	conn->state = STATE_DATA_RECEIVED;

	return STATE_DATA_RECEIVED;

remove_connection:
	rc = w_epoll_remove_ptr(epollfd, conn->sockfd, conn);
	DIE(rc < 0, "w_epoll_remove_ptr");

	/* remove current connection */
	connection_remove(conn);

	return STATE_CONNECTION_CLOSED;
}

/*
 * wait for asynchronous I/O operations
 * (eventfd or io_getevents)
 */
static void wait_aio(io_context_t ctx, int nops)
{
	struct io_event *events;
	int rc;

	/* TODO 1 - alloc structure */
	events = (struct io_event *) malloc(nops * sizeof(struct io_event));
	if (events == NULL){
		ERR("malloc");
	}

	/* Wait for async operations to finish 
	 *
	 * 	Use only io_getevents()
	 */
	rc = io_getevents(ctx, nops, nops, events, NULL);
	if (rc < 0){
		ERR("io_getevents");
	}

	free(events);
}


/*
 * Send message on socket.
 * Store message in send_buffer in struct connection.
 */

static enum connection_state send_message(struct connection *conn)
{
	ssize_t bytes_sent;
	int rc, i;
	char abuffer[64];

	rc = get_peer_address(conn->sockfd, abuffer, 64);
	if (rc < 0) {
		ERR("get_peer_address");
		goto remove_connection;
	}

	bytes_sent = send(conn->sockfd, conn->send_buffer, conn->send_len, 0);
	if (bytes_sent < 0) {
		dlog(LOG_ERR, "Error in communication to %s\n", abuffer);
		fprintf(stderr, "Error in communication to %s\n", abuffer);
		goto remove_connection;
	}
	if (bytes_sent == 0) {
		dlog(LOG_INFO, "Connection closed to %s\n", abuffer);
		fprintf(stderr, "Connection closed to %s\n", abuffer);
		goto remove_connection;
	}

	dlog(LOG_DEBUG, "Sending message to %s\n", abuffer);

	printf("--\n%s--\n", conn->send_buffer);

	if (conn->fd != -1){
		struct stat *buf = calloc(1, sizeof(struct stat));

		fstat(conn->fd, buf);

		/* TODO: trimis fisiere si in mod dinamic */
		if (strstr(request_path, "static") != NULL){
			fprintf(stderr, "Using sendfile\n");
			off_t total_sent = 0;
			int size = BUFSIZ;

			while (total_sent < buf->st_size){
				if (total_sent + BUFSIZ >= buf->st_size)
					size = total_sent + BUFSIZ - buf->st_size;
				fprintf(stderr, "%i %i\n", (int)total_sent, (int)buf->st_size);
				rc = sendfile(conn->sockfd, conn->fd, NULL, buf->st_size);
				if (rc == -1){
					ERR("sendfile\n");
				}
				else
					total_sent += rc;
			}
		}
		else{
			/* io_submit etc */
			int n_aio_ops;

			/* initializez o noua conexiune aici, eventfd?*/
			conn->efd = eventfd(0, 0);
			eefd = conn->efd;

			/* AIO context */
			io_context_t ctx;

			conn->iocbs = buf->st_size / BUFSIZ + (buf->st_size % BUFSIZ == 0 ? 0 : 1);
			
			/* Allocate iocb and piocb */
			conn->iocb = (struct iocb *) malloc(conn->iocbs * sizeof(*(conn->iocb)));
			if (conn->iocb == NULL){
				ERR("malloc");
			}

			conn->piocb = (struct iocb **) malloc(conn->iocbs * sizeof(*(conn->piocb)));
			if (conn->piocb == NULL){
				ERR("malloc");
			}

			for (i = 0; i < conn->iocbs; i++)
			{
				io_prep_pwrite(&(conn->iocb[i]), conn->fd, buffer, BUFSIZ, 0);
				conn->piocb[i] = &(conn->iocb[i]);
				io_set_eventfd(&(conn->iocb[i]), conn->efd);
			}

			/* Setup aio context */
			rc = io_setup(conn->iocbs, &ctx);
			if (rc < 0){
				ERR("io_setup");
			}

			/* Submit aio */
			n_aio_ops = io_submit(ctx, conn->iocbs, conn->piocb);
			if (n_aio_ops < 0){
				ERR("io_submit");
			}

			/* Wait for completion*/
			wait_aio(ctx, conn->iocbs);

			/* Destroy aio context */
			io_destroy(ctx);
		}
	
		free(buf);
	}

	/* all done - remove out notification */
	rc = w_epoll_update_ptr_in(epollfd, conn->sockfd, conn);
	DIE(rc < 0, "w_epoll_update_ptr_in");

	conn->state = STATE_DATA_SENT;

remove_connection:

	rc = w_epoll_remove_ptr(epollfd, conn->sockfd, conn);
	DIE(rc < 0, "w_epoll_remove_ptr");

	/* remove current connection */
	connection_remove(conn);

	return STATE_CONNECTION_CLOSED;
}

/*
 * Handle a client request on a client connection.
 */

static void handle_client_request(struct connection *conn)
{
	int rc;
	long unsigned int bytes_parsed;
	enum connection_state ret_state;

	ret_state = receive_message(conn);
	if (ret_state == STATE_CONNECTION_CLOSED)
		return;

	/* init HTTP_REQUEST parser */
	http_parser_init(&request_parser, HTTP_REQUEST);

	memset(request_path, 0, BUFSIZ);
	bytes_parsed = http_parser_execute(&request_parser, &settings_on_path, conn->recv_buffer, conn->recv_len);
	fprintf(stderr, "Parsed HTTP request (bytes: %lu), path: %s\n", bytes_parsed, request_path);
	
	memset(conn->pathname, 0, BUFSIZ);
	sprintf(conn->pathname, "%s%s", AWS_DOCUMENT_ROOT, request_path);
	conn->fd = open(conn->pathname, O_RDWR);
	
	memset(conn->send_buffer, 0, BUFSIZ);
	if (conn->fd == -1){
		sprintf(conn->send_buffer, "HTTP/1.0 404 Not Found\r\n\r\n");
		conn->send_len = strlen("HTTP/1.0 404 Not Found\r\n\r\n");
	}
	else{
		sprintf(conn->send_buffer, "HTTP/1.0 200 OK\r\n\r\n");
		conn->send_len = strlen("HTTP/1.0 200 OK\r\n\r\n");
	}

	/* add socket to epoll for out events */
	rc = w_epoll_update_ptr_inout(epollfd, conn->sockfd, conn);
	DIE(rc < 0, "w_epoll_add_ptr_inout");
}

int main(int argc, char **argv)
{
	int rc, bytes_sent,i;

	/* init multiplexing */
	epollfd = w_epoll_create();
	DIE(epollfd < 0, "w_epoll_create");

	/* create server socket */
	listenfd = tcp_create_listener(AWS_LISTEN_PORT, DEFAULT_LISTEN_BACKLOG);
	DIE(listenfd < 0, "tcp_create_listener");

	rc = w_epoll_add_fd_in(epollfd, listenfd);
	DIE(rc < 0, "w_epoll_add_fd_in");

	dlog(LOG_INFO, "Server waiting for connections on port %d\n", AWS_LISTEN_PORT);

	/* server main loop */
	while (1) {
		struct epoll_event rev;

		/* wait for events */
		rc = w_epoll_wait_infinite(epollfd, &rev);
		DIE(rc < 0, "w_epoll_wait_infinite");

		/*
		 * switch event types; consider
		 *   - new connection requests (on server socket)
		 *   - socket communication (on connection sockets)
		 */
		if (rev.data.fd == listenfd) {
			dlog(LOG_DEBUG, "New connection\n");
			if (rev.events & EPOLLIN)
				handle_new_connection();
		}
		else {
			if (rev.events & EPOLLIN) {
				dlog(LOG_DEBUG, "New message\n");
				handle_client_request(rev.data.ptr);
			}
			if (rev.events & EPOLLOUT) {
				dlog(LOG_DEBUG, "Ready to send message\n");
				send_message(rev.data.ptr);
			}
		}
	}

	return 0;
}
