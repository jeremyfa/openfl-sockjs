package sockjs;

import haxe.Json;
import openfl.Assets;
import sockjs.transport.SockJSTransportHttp;
import flash.external.ExternalInterface;

#if html5
import js.Lib;
#elseif cpp
import cpp.Lib;
#elseif neko
import haxe.macro.Expr.Function;
import neko.Lib;
#end


class SockJS
{

    // Used in order to find native related instance from static bindings
    private var _instanceId : Int;
    private static var _sUsedInstanceIds : Map<Int,SockJS>;

    // Active is true when native object exists
    private var _active : Bool;

    // Connected is true when socket is connected
    private var _connected : Bool;

    // Options
    private var _options : Dynamic;

    // Last error message
    private var _lastErrorMessage : String;

    // Callbacks
    private var _onOpenCallbacks : Array<Dynamic>;
    private var _onMessageCallbacks : Array<Dynamic>;
    private var _onCloseCallbacks : Array<Dynamic>;
    private var _onErrorCallbacks : Array<Dynamic>;

    #if android
    // Native bindings (JAVA)
    private static var _sSockJSInit;
    private static var _sSockJSSend;
    private static var _sSockJSReconnect;
    private static var _sSockJSClose;
    private static var _sNativeListener : NativeSockJSListener;
    #elseif ios
    // Native bindings (CPP)
    private static var _sSockJSInit = Lib.load("sockjs", "sockjs_init", 5);
    private static var _sSockJSSend = Lib.load("sockjs", "sockjs_send", 2);
    private static var _sSockJSReconnect = Lib.load("sockjs", "sockjs_reconnect", 1);
    private static var _sSockJSClose = Lib.load("sockjs", "sockjs_close", 1);
    #elseif html5
    #else
    #end

    private var _httpTransport : SockJSTransportHttp;
    private var _isExternalInterfaceAvailable : Bool;
    private static var _sDidConfigureExternalInterface : Bool;

    private static var _sFlashObjectProps : Dynamic;

    /**
     Initialize a new socket that points to the given URL and
     configured according to the optional parameters.
     */
    public function new(url:String, ?options:Dynamic)
    {
        // Init callback collections
        _onOpenCallbacks = [];
        _onMessageCallbacks = [];
        _onCloseCallbacks = [];
        _onErrorCallbacks = [];

        // Null last error message
        _lastErrorMessage = null;

        // Set options
        if (options != null) {
            _options = options;
        } else {
            _options = {};
        }

        // Set server URL
        _options.serverURL = url;

        // Set default values
        if (_options.clientURL == null && _options.clientJS == null) {
            _options.clientJS = Assets.getText("sockjs/js/sockjs-0.3.min.js");
        }

        //_options.forcePolling = true;

        if (_options.forcePolling) {
            //
        } else {
            #if android
            // Init native listener if needed
            if (_sNativeListener == null) {
                _sNativeListener = new NativeSockJSListener(_sHandleOpen, _sHandleMessage, _sHandleClose);

                _sSockJSInit = openfl.utils.JNI.createStaticMethod("sockjs/SockJS", "init", "(ILjava/lang/String;Lorg/haxe/lime/HaxeObject;)V");
                _sSockJSSend = openfl.utils.JNI.createStaticMethod("sockjs/SockJS", "send", "(ILjava/lang/String;)V");
                _sSockJSReconnect = openfl.utils.JNI.createStaticMethod("sockjs/SockJS", "reconnect", "(I)V");
                _sSockJSClose = openfl.utils.JNI.createStaticMethod("sockjs/SockJS", "close", "(I)V");
            }
            #end

            #if flash
            if (!_sDidConfigureExternalInterface) {
                // Check if external interface is usable for javascript
                if (ExternalInterface.available) {
                    try {
                        // Create test function
                        ExternalInterface.call("eval", "function sockjs_test_js_availability() { return 'yes'; }");
                        // Try to run function
                        var result : String = ExternalInterface.call("sockjs_test_js_availability");

                        if (result == "yes") {

                            ExternalInterface.addCallback("sockjs_cb_s_get_props", _sGetProps);
                            _sRetrieveEmbedObjectPropsForTagname("object", "sockjs_cb_s_get_props");
                            if (_sFlashObjectProps == null) {
                                _sRetrieveEmbedObjectPropsForTagname("embed", "sockjs_cb_s_get_props");
                            }

                            if (_sFlashObjectProps == null) {
                                _isExternalInterfaceAvailable = false;
                            } else {
                                _isExternalInterfaceAvailable = true;
                                ExternalInterface.addCallback("sockjs_cb_s_handleopen", _sHandleOpen);
                                ExternalInterface.addCallback("sockjs_cb_s_handlemessage", _sHandleMessage);
                                ExternalInterface.addCallback("sockjs_cb_s_handleclose", _sHandleClose);
                            }
                        } else {
                            _isExternalInterfaceAvailable = false;
                        }

                    } catch (e : Dynamic) {
                        _isExternalInterfaceAvailable = false;
                    }
                } else {
                    _isExternalInterfaceAvailable = false;
                }
                _sDidConfigureExternalInterface = true;
            }
            #end
        }

        // Compute instance id
        if (_sUsedInstanceIds == null) {
            _sUsedInstanceIds = [0 => this];
            _instanceId = 0;
        } else {
            var i : Int = 0;
            while (_sUsedInstanceIds[i] != null) {
                i++;
            }
            _sUsedInstanceIds.set(i, this);
            _instanceId = i;
        }

        _active = false;
        _connected = false;
    }

    /**
     Connect the newly configured socket.
     */
    public function connect() : Void
    {
        if (_instanceId == -1) return;

        if (_active) {
            if (_connected) return;

            if (_options.forcePolling) {
                _httpTransport.reconnect();
            } else {
                #if html5
                if (_options.clientJS != null) {
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+" = new window.SockJS(window._sockjs_js_serverURL);");
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+".onopen = function() { sockjs.SockJS._sHandleOpen("+_instanceId+") };");
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+".onclose = function() { sockjs.SockJS._sHandleClose("+_instanceId+") };");
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+".onmessage = function(e) { sockjs.SockJS._sHandleMessage("+_instanceId+",e.data) };");
                } else {
                    _httpTransport.reconnect();
                }
                #elseif flash
                if (_isExternalInterfaceAvailable) {
                    if (_options.clientJS != null) {
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+" = new window.SockJS(window._sockjs_js_serverURL);");
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onopen = function() { document.getElementById('"+_sFlashObjectProps.id+"').sockjs_cb_s_handleopen("+_instanceId+") };");
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onclose = function() { document.getElementById('"+_sFlashObjectProps.id+"').sockjs_cb_s_handleclose("+_instanceId+") };");
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onmessage = function(e) { document.getElementById('"+_sFlashObjectProps.id+"').sockjs_cb_s_handlemessage("+_instanceId+",e.data) };");
                    } else {
                        _httpTransport.reconnect();
                    }
                } else {
                    _httpTransport.reconnect();
                }
                #elseif android
                _sSockJSReconnect(_instanceId);
                #elseif ios
                _sSockJSReconnect(_instanceId);
                #else
                _httpTransport.reconnect();
                #end
            }
        } else {

            _active = true;

            if (_options.forcePolling) {
                _httpTransport = new SockJSTransportHttp(_instanceId, _options.serverURL, _sHandleOpen, _sHandleMessage, _sHandleClose, _sHandleCustomError);
            } else {
                #if html5
                if (_options.clientJS != null) {
                    Lib.eval("(function(){ var SockJS; (function(){"+_options.clientJS+"})(); window.SockJS = SockJS; })();");
                    Lib.eval("window._sockjs_js_serverURL = "+Json.stringify(_options.serverURL)+";");
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+" = new window.SockJS(window._sockjs_js_serverURL);");
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+".onopen = function() { sockjs.SockJS._sHandleOpen("+_instanceId+") };");
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+".onclose = function() { sockjs.SockJS._sHandleClose("+_instanceId+") };");
                    Lib.eval("window._sockjs_js_socket_"+_instanceId+".onmessage = function(e) { sockjs.SockJS._sHandleMessage("+_instanceId+",e.data) };");
                } else {
                    _httpTransport = new SockJSTransportHttp(_instanceId, _options.serverURL, _sHandleOpen, _sHandleMessage, _sHandleClose, _sHandleCustomError);
                }
                #elseif flash
                if (_isExternalInterfaceAvailable) {
                    if (_options.clientJS != null) {
                        var escaped:String = StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(_options.clientJS, '\\', '[[HXFL_B]]'), '"', '[[HXFL_Q]]'), "\n", '[[HXFL_N]]'), "\r", '[[HXFL_R]]');
                        ExternalInterface.call("eval", "for (var key in document.embeds) { /*if (document.embeds[key].sockjs_test_js_availability) {*/ console.log(key); /*}*/ }");
                        ExternalInterface.call("eval", "eval(\""+escaped+"\".split('[[HXFL_B]]').join('\\\\\\\\').split('[[HXFL_Q]]').join('\"').split('[[HXFL_N]]').join(\"\\\\n\").split('[[HXFL_R]]').join(\"\\\\r\"));");
                        ExternalInterface.call("eval", "window._sockjs_js_serverURL = "+Json.stringify(_options.serverURL)+";");
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+" = new window.SockJS(window._sockjs_js_serverURL);");
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onopen = function() { document.getElementById('"+_sFlashObjectProps.id+"').sockjs_cb_s_handleopen("+_instanceId+") };");
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onclose = function() { document.getElementById('"+_sFlashObjectProps.id+"').sockjs_cb_s_handleclose("+_instanceId+") };");
                        ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onmessage = function(e) { document.getElementById('"+_sFlashObjectProps.id+"').sockjs_cb_s_handlemessage("+_instanceId+",e.data) };");
                    } else {
                        _httpTransport = new SockJSTransportHttp(_instanceId, _options.serverURL, _sHandleOpen, _sHandleMessage, _sHandleClose, _sHandleCustomError);
                    }
                } else {
                    _httpTransport = new SockJSTransportHttp(_instanceId, _options.serverURL, _sHandleOpen, _sHandleMessage, _sHandleClose, _sHandleCustomError);
                }
                #elseif android
                _sSockJSInit(_instanceId, Json.stringify(_options), _sNativeListener);
                #elseif ios
                _sSockJSInit(_instanceId, Json.stringify(_options), _sHandleOpen, _sHandleMessage, _sHandleClose);
                #else
                _httpTransport = new SockJSTransportHttp(_instanceId, _options.serverURL, _sHandleOpen, _sHandleMessage, _sHandleClose, _sHandleCustomError);
                #end
            }
        }
    }

    /**
     Return true if the socket is currently connected.
     */
    public function isConnected() : Bool
    {
        return _connected;
    }

    /**
     Add an open event callback.
     It will be called when the socked successfuly connected to the server.
     */
    public function onOpen(callback:Void->Void) : Void
    {
        if (_instanceId == -1) return;
        _onOpenCallbacks.push(callback);
    }

    /**
     Add a message event callback.
     Everytime a message is received from the server, the callback will be called.
     */
    public function onMessage(callback:String->Void) : Void
    {
        if (_instanceId == -1) return;
        _onMessageCallbacks.push(callback);
    }

    /**
     Add a close event callback.
     The callback will be called when the socket has been closed.
     It will happen if the internet connection is lost, or if the server is down...
     */
    public function onClose(callback:Void->Void) : Void
    {
        if (_instanceId == -1) return;
        _onCloseCallbacks.push(callback);
    }

    /**
     Add an error event callback.
     The callback will be called when the socket failed to connect.
     */
    public function onError(callback:String->Void) : Void
    {
        if (_instanceId == -1) return;
        _onErrorCallbacks.push(callback);
    }

    /**
     Send a message to the server.
     @param message The message to send
     */
    public function send(message:String) : Void
    {
        if (_instanceId == -1) return;
        if (message == null) return;

        if (_options.forcePolling) {
            _httpTransport.send(message);
        } else {
            #if html5
            if (_options.clientJS != null) {
                Lib.eval("window._sockjs_js_socket_"+_instanceId+".send("+Json.stringify(message)+");");
            } else {
                _httpTransport.send(message);
            }
            #elseif flash
            if (_isExternalInterfaceAvailable) {
                if (_options.clientJS != null) {
                    var escaped:String = StringTools.replace(StringTools.replace(StringTools.replace(StringTools.replace(message, '\\', '[[HXFL_B]]'), '"', '[[HXFL_Q]]'), "\n", '[[HXFL_N]]'), "\r", '[[HXFL_R]]');
                    ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".send(\""+escaped+"\".split('[[HXFL_B]]').join('\\\\\\\\').split('[[HXFL_Q]]').join('\"').split('[[HXFL_N]]').join(\"\\\\n\").split('[[HXFL_R]]').join(\"\\\\r\"));");
                } else {
                    _httpTransport.send(message);
                }
            } else {
                _httpTransport.send(message);
            }
            #elseif android
            _sSockJSSend(_instanceId, message);
            #elseif ios
            _sSockJSSend(_instanceId, message);
            #else
            _httpTransport.send(message);
            #end
        }
    }

    /**
     Close the socket/connection.
     The socket can still be reused later by
     calling the connect() method.
     */
    public function close() : Void
    {
        if (_instanceId == -1) return;
        if (!_active) return;
        _active = false;
        _connected = false;

        if (_options.forcePolling) {
            _httpTransport.close();
        } else {
            #if html5
            if (_options.clientJS != null) {
                Lib.eval("window._sockjs_js_socket_"+_instanceId+".onopen = null;");
                Lib.eval("window._sockjs_js_socket_"+_instanceId+".onclose = null;");
                Lib.eval("window._sockjs_js_socket_"+_instanceId+".onmessage = null;");
                Lib.eval("window._sockjs_js_socket_"+_instanceId+".close();");
                Lib.eval("window._sockjs_js_socket_"+_instanceId+" = null;");
            } else {
                _httpTransport.close();
            }
            #elseif flash
            if (_isExternalInterfaceAvailable) {
                if (_options.clientJS != null) {
                    ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onopen = null;");
                    ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onclose = null;");
                    ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".onmessage = null;");
                    ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+".close();");
                    ExternalInterface.call("eval", "window._sockjs_js_socket_"+_instanceId+" = null;");
                } else {
                    _httpTransport.close();
                }
            } else {
                _httpTransport.close();
            }
            #elseif android
            _sSockJSClose(_instanceId);
            #elseif ios
            _sSockJSClose(_instanceId);
            #else
            _httpTransport.close();
            #end
        }
    }

    /**
     Destroy all resources related to this socket.
     This should be called when the socket is no longuer used.
     Once a socket is destroyed, it is not usable anymore and a
     new one need to be created for future connections.
     */
    public function destroy() : Void
    {
        close();
        if (_instanceId == -1) return;
        _sUsedInstanceIds.remove(_instanceId);
        _instanceId = -1;
    }

    private function _handleOpen() : Void
    {
        if (_instanceId == -1) return;
        _connected = true;
        for (callback in _onOpenCallbacks) {
            callback();
        }
    }

    private function _handleMessage(message:String) : Void
    {
        if (_instanceId == -1) return;
        for (callback in _onMessageCallbacks) {
            callback(message);
        }
    }

    private function _handleClose() : Void
    {
        if (_instanceId == -1) return;
        if (!_connected) {
            var errorMessage:String = "Failed to connect.";
            if (_lastErrorMessage != null) {
                errorMessage = "Failed to connect: "+_lastErrorMessage;
                _lastErrorMessage = null;
            }
            for (callback in _onErrorCallbacks) {
                callback(errorMessage);
            }
        } else {
            _connected = false;
            for (callback in _onCloseCallbacks) {
                callback();
            }
        }

        if (_options.reconnect == true) {
            haxe.Timer.delay(connect, 2500);
        }
    }
    
    private static function _sHandleOpen(instanceId:Int) : Void
    {
        var instance:SockJS = _sUsedInstanceIds.get(instanceId);
        if (instance != null) {
            instance._handleOpen();
        }
    }
    
    private static function _sHandleMessage(instanceId:Int, message:String) : Void
    {
        var instance:SockJS = _sUsedInstanceIds.get(instanceId);
        if (instance != null) {
            instance._handleMessage(message);
        }
    }
    
    private static function _sHandleClose(instanceId:Int) : Void
    {
        var instance:SockJS = _sUsedInstanceIds.get(instanceId);
        if (instance != null) {
            instance._handleClose();
        }
    }
    
    private static function _sHandleCustomError(instanceId:Int, error:String) : Void
    {
        var instance:SockJS = _sUsedInstanceIds.get(instanceId);
        if (instance != null) {
            instance._lastErrorMessage = error;
        }
    }

    /**
     Code inspired from: http://analogcode.com/p/JSTextReader/
     */
    private static function _sRetrieveEmbedObjectPropsForTagname(tagName:String, callbackName:String) : Void
    {
        var generateId:String = "if (!elts[i].getAttribute('id')) {elts[i].setAttribute('id','asorgid_'+Math.floor(Math.random()*100000));}";

        var js:String = "var elts = document.getElementsByTagName('"+tagName+"'); for (var i=0;i<elts.length;i++) {if(typeof elts[i]."+callbackName+" != 'undefined') { "+generateId+" var props = {}; props.id = elts[i].getAttribute('id'); for (var x=0; x < elts[i].attributes.length; x++) { props[elts[i].attributes[x].nodeName] = elts[i].attributes[x].nodeValue;} elts[i]."+callbackName+"(props); }}";
        ExternalInterface.call("eval", js);
    }

    private static function _sGetProps(props:Dynamic) : Void
    {
        if (props.id != null && props.id.length > 0) {
            _sFlashObjectProps = props;
        }
    }
}

private class NativeSockJSListener
{
    private var _handleOpen : Dynamic;
    private var _handleMessage : Dynamic;
    private var _handleClose : Dynamic;

    public function new(handleOpen:Dynamic, handleMessage:Dynamic, handleClose:Dynamic)
    {
        _handleOpen = handleOpen;
        _handleMessage = handleMessage;
        _handleClose = handleClose;
    }

    public function onOpen(instanceId:Int) : Void
    {
        _handleOpen(instanceId);
    }

    public function onMessage(instanceId:Int, message:String) : Void
    {
        _handleMessage(instanceId, message);
    }

    public function onClose(instanceId:Int) : Void
    {
        _handleClose(instanceId);
    }
}