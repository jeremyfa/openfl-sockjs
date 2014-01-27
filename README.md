OpenFL SockJS client library
============================

Cross-platform SockJS client library for realtime remoting with OpenFL apps and a SockJS websocket server.

This library allows OpenFL/Haxe apps to connect to SockJS servers. It has been tested on iOS, Android, C++ (tested on mac, but should be OK on windows too), Neko, Flash, Flash inside HTML5 and HTML5.

SockJS server can run on Node.js, Python or even Java plarforms (more info: https://github.com/sockjs/sockjs-client).

The idea is that SockJS can use websockets if they are available but is able to fall back to other protocols like HTTP polling or HTTP streaming. This allow to have a realtime socket emulation library that can work in bad conditions such as a very restricting proxy and so on.

### How does it work?

The most common use of SockJS is with the javascript client library as it is able to choose the best protocol available depending on the current network and the device capabilities.

That said, javascript is not available on all OpenFL targets. It is, however, available on iOS and Android targets through WebViews and on Flash target when embedded inside a web page using the ExternalInterface API. It is of course also available on HTML5 target!

#### Then, what about C++ or Neko targets? Or standalone Flash?

When running on a platform that doesn't allow the use of the SockJS javascript client, the OpenFL SockJS library falls back to a full Haxe/OpenFL implementation that can connect to SockJS server using HTTP polling. It is a bit less efficient than websockets but will still work fine, even behind a restrictive proxy.

### How to use

#### Import SockJS class

``` haxe
import sockjs.SockJS;
```

#### Create and connect socket

``` haxe
// Create socket (automatically reconnect when connection is lost).
var socket:SockJS = new SockJS("http://yourdomain.com/sockjs", {reconnect: true});

// Listen open event
socket.onOpen(function() {
    trace("Socket did open");
});

// Listen message event
socket.onMessage(function(message) {
    trace("Socket did receive message: "+message);
});

// Listen error event
socket.onError(function(error) {
    trace("Socket failed with error: "+error);
});

// Listen close event
socket.onClose(function() {
    trace("Socket did close");
});

// Connect socket
socket.connect();
```

#### Send data to the server

``` haxe
socket.send("Hello!");
```
