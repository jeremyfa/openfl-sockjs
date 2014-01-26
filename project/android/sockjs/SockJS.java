package sockjs;

import org.haxe.lime.HaxeObject;
import org.haxe.extension.Extension;
import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;
import java.lang.Runnable;

import android.annotation.SuppressLint;
//import android.webkit.JavascriptInterface; // Uncomment if target >= 4.3
import android.webkit.WebView;
import android.os.Handler;
import android.util.Log;


//@SuppressLint("SetJavaScriptEnabled")
public class SockJS {
    public static SockJSInstance[] sInstances;
    public static HaxeObject sListener;

    public static void init(final int instanceId, final String opts, final HaxeObject listener)
    {
        Extension.callbackHandler.post(new Runnable() {
            public void run() {

                if (sInstances == null) {
                    sInstances = new SockJSInstance[16];
                    for (int i = 0; i < 16; i++)
                        sInstances[i] = null;
                    sListener = listener;
                }

                sInstances[instanceId] = new SockJSInstance(instanceId, opts);
            }
        });
    }

    public static void send(final int instanceId, final String msg)
    {
        Extension.callbackHandler.post(new Runnable() {
            public void run() {

                SockJSInstance instance = sInstances[instanceId];
                if (instance == null) return;

                // Create escaped message
                JSONArray array = new JSONArray();
                array.put(msg);
                String message = array.toString();
                message = message.substring(1, message.length()-1);
                
                // Execute js to send message
                instance.mWebView.loadUrl("javascript:socket.send("+message+");");
            }
        });
    }

    public static void reconnect(final int instanceId)
    {
        Extension.callbackHandler.post(new Runnable() {
            public void run() {

                SockJSInstance instance = sInstances[instanceId];
                if (instance == null) return;
                
                instance.mWebView.loadUrl("javascript:socket = new SockJS(serverURL); socket.onopen = function() { sockjs_android.onopen() }; socket.onclose = function() { sockjs_android.onclose() }; socket.onmessage = function(e) { sockjs_android.onmessage(e.data) };");
            }
        });
    }
    
    public static void close(final int instanceId)
    {
        Extension.callbackHandler.post(new Runnable() {
            public void run() {

                SockJSInstance instance = sInstances[instanceId];
                if (instance == null) return;
                
                // Destroy
                instance.mWebView.destroy();
                sInstances[instanceId] = null;
            }
        });
    }
    
    private static class SockJSInstance
    {
        private int mInstanceId;
        private WebView mWebView;
        
        public SockJSInstance(int instanceId, String opts)
        {
            mInstanceId = instanceId;
            
            // Extract options
            JSONObject options = null;
            try {
                options = new JSONObject(opts);
            } catch (JSONException e) {
                Log.e("lime", "Failed parse JSON", e);
                return;
            }
            
            // Create webview
            mWebView = new WebView(Extension.mainContext);
            mWebView.getSettings().setJavaScriptEnabled(true);

            StringBuilder html = new StringBuilder();
            String serverURL = null;
            try {
                serverURL = options.getString("serverURL");
                
                html.append("<html><head>");
                if (options.has("clientURL")) {
                    html.append("<script src=\"");
                    html.append(options.getString("clientURL"));
                    html.append("\"></script>");
                } else if (options.has("clientJS")) {
                    html.append("<script>\n");
                    html.append(options.getString("clientJS"));
                    html.append("\n</script>");
                }
                html.append("<script>");
                html.append("var serverURL = \"");
                html.append(serverURL);
                html.append("\";");
                html.append("var socket = new SockJS(serverURL);");
                html.append("socket.onopen = function() { sockjs_android.onopen() };");
                html.append("socket.onclose = function() { sockjs_android.onclose() };");
                html.append("socket.onmessage = function(e) { sockjs_android.onmessage(e.data) };");
                html.append("</script></head><body></body></html>");
                
            } catch (JSONException e) {
                Log.e("lime", "Failed to generate HTML", e);
                return;
            }
            
            // Set javascript interface
            mWebView.addJavascriptInterface(new SockJSJavascriptInterface(), "sockjs_android");
            
            // Load html
            mWebView.loadDataWithBaseURL(serverURL, html.toString(), "text/html", "UTF-8", null);
        }
        
        /**
         * Capture events sent from webView
         */
        private class SockJSJavascriptInterface {
            public SockJSJavascriptInterface() { }
            
            //@JavascriptInterface // Uncomment if target >= 4.3
            public void onopen() {
                final int instanceId = mInstanceId;
                Extension.callbackHandler.post(new Runnable() {
                    public void run() {
                        Log.d("lime", "ON OPEN "+instanceId);
                        sListener.call1("onOpen", instanceId);
                    }
                });
            }
            
            //@JavascriptInterface // Uncomment if target >= 4.3
            public void onmessage(final String message) {
                final int instanceId = mInstanceId;
                Extension.callbackHandler.post(new Runnable() {
                    public void run() {
                        Log.d("lime", "ON MESSAGE "+instanceId+" "+message);
                        sListener.call2("onMessage", instanceId, message);
                    }
                });
            }

            //@JavascriptInterface // Uncomment if target >= 4.3
            public void onclose() {
                final int instanceId = mInstanceId;
                Extension.callbackHandler.post(new Runnable() {
                    public void run() {
                        Log.d("lime", "ON CLOSE "+instanceId);
                        sListener.call1("onClose", instanceId);
                    }
                });
            }
        }
    }
}
