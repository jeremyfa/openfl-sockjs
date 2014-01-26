#ifndef ENGINEIO_H
#define ENGINEIO_H


namespace sockjs {
	
	void init(int instanceId, const char *options, value _onEventCallback, value _onMessageCallback, value _onCloseCallback);
    void send(int instanceId, const char *message);
    void reconnect(int instanceId);
    void close(int instanceId);
	
}


#endif