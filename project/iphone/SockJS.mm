
#ifndef HXCPP_EXTERN_CLASS_ATTRIBUTES
    #define HXCPP_EXTERN_CLASS_ATTRIBUTES
#endif

#import <UIKit/UIKit.h>
#include <hx/Macros.h>
#include <hx/CFFI.h>
#include "Utils.h"

typedef void (*SockJSOnOpenFunctionType)(int instanceId);
typedef void (*SockJSOnMessageFunctionType)(int instanceId, NSString *);
typedef void (*SockJSOnCloseFunctionType)(int instanceId);

@interface SockJSWebViewDelegate : NSObject <UIWebViewDelegate>

@property (nonatomic) int instanceId;
@property (nonatomic) SockJSOnOpenFunctionType onOpen;
@property (nonatomic) SockJSOnMessageFunctionType onMessage;
@property (nonatomic) SockJSOnCloseFunctionType onClose;

@end

@implementation SockJSWebViewDelegate

@synthesize instanceId;
@synthesize onOpen;
@synthesize onMessage;
@synthesize onClose;

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSString *requestString = [[request URL] absoluteString];

    if ([requestString hasPrefix:@"jsf:"]) {
        NSArray *components = [requestString componentsSeparatedByString:@":"];
        NSUInteger len = [components count];
        if (len != 3) return NO;
        unichar event = [components[1] characterAtIndex:0];
        if (event == 'm') {
            NSString *message = [components[2] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
            self.onMessage(self.instanceId, message);
        } else if (event == 'o') {
            self.onOpen(self.instanceId);
        }else if (event == 'c') {
            self.onClose(self.instanceId);
        }
        return NO;
    }

    return YES;
}

@end

namespace sockjs
{
    NSMutableArray *webViews = nil;
    NSMutableArray *webViewDelegates = nil;
    SockJSWebViewDelegate *webViewDelegate;

    AutoGCRoot *onOpenCallback = 0;
    AutoGCRoot *onMessageCallback = 0;
    AutoGCRoot *onCloseCallback = 0;

    void onOpen(int instanceId);
    void onMessage(int instanceId, NSString *message);
    void onClose(int instanceId);
    
    void init(int instanceId, const char *opts, value _onOpenCallback, value _onMessageCallback, value _onCloseCallback)
    {
        // Parse JSON options
        NSDictionary *options = [NSJSONSerialization
            JSONObjectWithData:[[[NSString alloc] initWithUTF8String:opts] dataUsingEncoding:NSUTF8StringEncoding]
            options:NSJSONReadingMutableContainers
            error:NULL];

        // The first time, create an array of 16 elements
        // (we will never reach that number anyway)
        if (!webViews) {
            webViews = [[NSMutableArray alloc] init];
            webViewDelegates = [[NSMutableArray alloc] init];
            for (int i = 0; i < 16; i++) {
                [webViews addObject:[NSNull null]];
                [webViewDelegates addObject:[NSNull null]];
            }

            // Assign bridge functions if needed as well
            onOpenCallback = new AutoGCRoot(_onOpenCallback);
            onMessageCallback = new AutoGCRoot(_onMessageCallback);
            onCloseCallback = new AutoGCRoot(_onCloseCallback);
        }

        // Create a webView that will not be visible on screen
        UIWebView *webView = [[UIWebView alloc] initWithFrame:CGRectMake(-100, -100, 1, 1)];

        // Configure and assign delegate
        SockJSWebViewDelegate *delegate = [[SockJSWebViewDelegate alloc] init];
        delegate.onOpen = &onOpen;
        delegate.onMessage = &onMessage;
        delegate.onClose = &onClose;
        webView.delegate = delegate;

        // Keep track of webview and its delegate
        [webViews replaceObjectAtIndex:instanceId withObject:webView];
        [webViewDelegates replaceObjectAtIndex:instanceId withObject:delegate];
        
        // Add web view to window (in order to be sure it will perform correctly)
        [[[UIApplication sharedApplication] keyWindow] addSubview:webView];

        NSMutableString *html = [NSMutableString string];
        [html appendString:@"<html><head>"];
        if ([options objectForKey:@"clientURL"]) {
            [html appendString:@"<script src=\""];
            [html appendString:[options objectForKey:@"clientURL"]];
            [html appendString:@"\"></script>"];
        } else if ([options objectForKey:@"clientJS"]) {
            [html appendString:@"<script>\n"];
            [html appendString:[options objectForKey:@"clientJS"]];
            [html appendString:@"\n</script>"];
        }
        [html appendString:@"<script>"];
        [html appendString:@"var trigger_sockjs_event = function(event, message) {"];
        [html appendString:@"var iframe = document.createElement(\"IFRAME\");"];
        [html appendString:@"iframe.setAttribute(\"src\", \"jsf:\" + event + \":\" + encodeURIComponent(''+message));"];
        [html appendString:@"document.documentElement.appendChild(iframe);"];
        [html appendString:@"iframe.parentNode.removeChild(iframe);"];
        [html appendString:@"iframe = null;"];
        [html appendString:@"};"];
        [html appendString:@"var serverURL = \""];
        [html appendString:[options objectForKey:@"serverURL"]];
        [html appendString:@"\";"];
        [html appendString:@"var socket = new SockJS(serverURL);"];
        [html appendString:@"socket.onopen = function() { trigger_sockjs_event('o','') };"];
        [html appendString:@"socket.onclose = function() { trigger_sockjs_event('c','') };"];
        [html appendString:@"socket.onmessage = function(e) { trigger_sockjs_event('m',e.data) };"];
        [html appendString:@"</script></head><body></body></html>"];
        [webView loadHTMLString:html baseURL:[NSURL URLWithString:[options objectForKey:@"serverURL"]]];
    }

    void send(int instanceId, const char *chars)
    {
        // Retrieve webView
        UIWebView *webView = [webViews objectAtIndex:instanceId];

        // Handle case where webview doesn't exist
        if ((id)webView == [NSNull null]) return;

        // Get and escape message to send
        NSMutableString *escapedString = [NSMutableString string];
        while (*chars)
        {
            if (*chars == '\\')
                [escapedString appendString:@"\\\\"];
            else if (*chars == '"')
                [escapedString appendString:@"\\\""];
            else if (*chars < 0x1F || *chars == 0x7F)
                [escapedString appendFormat:@"\\u%04X", (int)*chars];
            else
                [escapedString appendFormat:@"%c", *chars];
            ++chars;
        }

        // Execute js
        [webView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"socket.send(\"%@\");", escapedString]];
    }

    void reconnect(int instanceId)
    {
        // Retrieve webView
        UIWebView *webView = [webViews objectAtIndex:instanceId];

        // Reset SockJS
        [webView stringByEvaluatingJavaScriptFromString:@"socket = new SockJS(serverURL); socket.onopen = function() { trigger_sockjs_event('o','') }; socket.onclose = function() { trigger_sockjs_event('c','') }; socket.onmessage = function(e) { trigger_sockjs_event('m',e.data) };"];
    }

    void close(int instanceId)
    {
        // Retrieve webView
        UIWebView *webView = [webViews objectAtIndex:instanceId];
        // Retrieve delegate
        SockJSWebViewDelegate *delegate = [webViewDelegates objectAtIndex:instanceId];

        // Put null values in arrays
        [webViews replaceObjectAtIndex:instanceId withObject:[NSNull null]];
        [webViewDelegates replaceObjectAtIndex:instanceId withObject:[NSNull null]];

        // Release them
        if ((id)webView != [NSNull null]) {
            [webView stopLoading];
            [webView removeFromSuperview];
            webView = nil;
            delegate = nil;
        }
    }
    
    void onOpen(int instanceId)
    {
        val_call1(onOpenCallback->get(), alloc_int(instanceId));
    }
    
    void onMessage(int instanceId, NSString *event)
    {
        val_call2(onMessageCallback->get(), alloc_int(instanceId), alloc_string([event cStringUsingEncoding:NSUTF8StringEncoding]));
    }
    
    void onClose(int instanceId)
    {
        val_call1(onCloseCallback->get(), alloc_int(instanceId));
    }
}