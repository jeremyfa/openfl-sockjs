package sockjs.transport;

import haxe.Json;
import flash.net.URLLoader;
import flash.net.URLRequest;
import flash.net.URLVariables;
import flash.events.Event;
import flash.events.IOErrorEvent;
import haxe.Http;

/**
 Basic HTTP-polling transport for sockjs.
 This implementation will garantee that haxe program can connect on sockjs on any platform,
 event the ones without websocket transport.
 */
class SockJSTransportHttp
{
    private var _instanceId : Int;

    private var _onOpenCallback : Int->Void;
    private var _onMessageCallback : Int->String->Void;
    private var _onCloseCallback : Int->Void;
    private var _onCustomErrorCallback : Int->String->Void;

    private var _serverId : String;
    private var _sessionId : String;
    private var _serverURL : String;

    private var _connected : Bool;
    private var _closed : Bool;
    private var _sending : Bool;
    private var _willStartSendRequest : Bool;

    private var _currentPollLoader : URLLoader;
    private var _currentSendLoader : URLLoader;

    private var _messagesToSend : Array<String>;

    public function new(instanceId : Int, serverURL : String, onOpenCallback : Int->Void, onMessageCallback : Int->String->Void, onCloseCallback : Int->Void, ?onCustomErrorCallback : Int->String->Void)
    {
        // Configure context
        _instanceId = instanceId;
        _serverId = ""+Std.random(1000);
        if (_serverId.length < 3) _serverId = "0"+_serverId;
        if (_serverId.length < 3) _serverId = "0"+_serverId;
        _sessionId = _sRandomString(8);
        _serverURL = serverURL;
        _connected = false;
        _closed = false;
        _sending = false;
        _willStartSendRequest = false;
        _messagesToSend = [];

        // Assign callbacks
        _onOpenCallback = onOpenCallback;
        _onMessageCallback = onMessageCallback;
        _onCloseCallback = onCloseCallback;
        _onCustomErrorCallback = onCustomErrorCallback;

        _performPollRequest();
    }

    public function reconnect() : Void
    {
        if (_closed) _closed = false;

        // Stop any running connection
        _stopRunningRequests();
        // Create new session id
        _sessionId = _sRandomString(8);

        _performPollRequest();
    }

    public function close() : Void
    {
        _closed = true;
        _stopRunningRequests();
    }

    public function send(message:String) : Void
    {
        if (_closed) return;

        _messagesToSend.push(message);
        if (!_willStartSendRequest) {
            _willStartSendRequest = true;
            haxe.Timer.delay(_performSendRequest, 1);
        }
    }

    private function _performPollRequest() : Void
    {
        var request:URLRequest = new URLRequest(_serverURL + "/" + _serverId + "/" + _sessionId + "/xhr");
        request.method = "POST";

        // If we don't set any post data, flash seems to keep sending GET requests. Sad :-(
        var variables:URLVariables = new URLVariables();
        variables._ = "";
        request.data = variables;

        _currentPollLoader = new URLLoader();
        _currentPollLoader.addEventListener(Event.COMPLETE, _onPollComplete);
        _currentPollLoader.addEventListener(IOErrorEvent.IO_ERROR, _onPollError);

        try {
            _currentPollLoader.load(request);
        }
        catch (e:Dynamic) {
            if (_connected || !_closed) {
                _connected = false;
                _closed = true;
                _stopRunningRequests();
                if (_onCustomErrorCallback != null) {
                    _onCustomErrorCallback(_instanceId, Std.string(e));
                }
                _onCloseCallback(_instanceId);
            }
        }
    }

    private function _onPollComplete(e:Event) : Void
    {
        if (_currentPollLoader == null) return;
        var data:String = _currentPollLoader.data;
        _currentPollLoader.removeEventListener(Event.COMPLETE, _onPollComplete);
        _currentPollLoader.removeEventListener(IOErrorEvent.IO_ERROR, _onPollError);
        _currentPollLoader = null;

        if (_closed) return;

        if (data.length > 0) {
            var type:String = data.charAt(0);
            if (type == 'a') {
                if (_connected) {
                    var messages : Dynamic = Json.parse(data.substring(1));
                    if (Std.is(messages, Array)) {
                        var len:Int = messages.length;
                        for (i in 0...len) {
                            _onMessageCallback(_instanceId, messages[i]);
                        }
                    }
                }

            } else if (type == 'o') {
                if (!_connected) {
                    _connected = true;
                    _onOpenCallback(_instanceId);
                }

            } else if (type == 'c') {
                if (_connected || !_closed) {
                    _connected = false;
                    _closed = true;
                    _stopRunningRequests();
                    _onCloseCallback(_instanceId);
                }

                // Stop polling
                return;
            }
        }

        // Continue polling
        _performPollRequest();
    }

    private function _onPollError(e:Event) : Void
    {
        _stopRunningRequests();

        if (_closed) return;

        _onCloseCallback(_instanceId);
    }

    private function _performSendRequest() : Void
    {
        _willStartSendRequest = false;
        if (_sending) return;

        // Perform send HTTP query
        //var req:Http = new Http(_serverURL + "/" + _serverId + "/" + _sessionId + "/jsonp_send");

        var messagesJSON:String = Json.stringify(_messagesToSend);
        _messagesToSend = [];

        var request:URLRequest = new URLRequest(_serverURL + "/" + _serverId + "/" + _sessionId + "/jsonp_send");
        request.method = "POST";
        _currentSendLoader = new URLLoader();
        _currentSendLoader.addEventListener(Event.COMPLETE, _onSendComplete);
        _currentSendLoader.addEventListener(IOErrorEvent.IO_ERROR, _onSendError);
        //request.contentType = "application/json";
        
        var variables:URLVariables = new URLVariables();
        variables.d = messagesJSON;
        request.data = variables;

        _currentSendLoader.load(request);
    }

    private function _onSendComplete(e:Event) : Void
    {
        if (_currentSendLoader == null) return;
        var data:String = _currentSendLoader.data;
        _currentSendLoader.removeEventListener(Event.COMPLETE, _onSendComplete);
        _currentSendLoader.removeEventListener(IOErrorEvent.IO_ERROR, _onSendError);
        _currentSendLoader = null;

        _sending = false;

        // If there are new messages to send, send them
        if (_messagesToSend.length > 0) {
            _performSendRequest();
        }
    }

    private function _onSendError(e:Event) : Void
    {
        _stopRunningRequests();

        _sending = false;

        if (_connected) {
            _connected = false;
            _onCloseCallback(_instanceId);
        }
    }

    private function _stopRunningRequests() : Void
    {
        if (_currentPollLoader != null) {
            try {
                _currentPollLoader.removeEventListener(Event.COMPLETE, _onPollComplete);
                _currentPollLoader.removeEventListener(IOErrorEvent.IO_ERROR, _onPollError);
                _currentPollLoader.close();
            } catch (e:Dynamic) {}
            _currentPollLoader = null;
        }
        if (_currentSendLoader != null) {
            try {
                _currentSendLoader.removeEventListener(Event.COMPLETE, _onSendComplete);
                _currentSendLoader.removeEventListener(IOErrorEvent.IO_ERROR, _onSendError);
                _currentSendLoader.close();
            } catch (e:Dynamic) {}
            _currentSendLoader = null;
        }
    }

    /**
     Return a random string of a certain length.
     You can optionally specify 
     which characters to use, otherwise the default is (a-zA-Z0-9)
     Taken and modified from: https://github.com/jasononeil/hxrandom/blob/master/src/Random.hx
     */
    public static function _sRandomString(length:Int, ?charactersToUse = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_") : String
    {
        var str : String = "";
        var len : Int = charactersToUse.length - 1;
        for (i in 0...length)
        {
            str += charactersToUse.charAt(Std.random(len));
        }
        return str;
    }
}