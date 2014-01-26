#ifndef STATIC_LINK
#define IMPLEMENT_API
#endif

#if defined(HX_WINDOWS) || defined(HX_MACOS) || defined(HX_LINUX)
#define NEKO_COMPATIBLE
#endif


#include <hx/CFFI.h>
#include "Utils.h"


using namespace sockjs;

#ifdef IPHONE

static void sockjs_init(value instanceId, value options, value _onOpenCallback, value _onMessageCallback, value _onCloseCallback)
{
    init(val_int(instanceId), val_string(options), _onOpenCallback, _onMessageCallback, _onCloseCallback);
}
DEFINE_PRIM(sockjs_init, 5);

static void sockjs_send(value instanceId, value event)
{
    send(val_int(instanceId), val_string(event));
}
DEFINE_PRIM(sockjs_send, 2);

static void sockjs_reconnect(value instanceId)
{
    reconnect(val_int(instanceId));
}
DEFINE_PRIM(sockjs_reconnect, 1);

static void sockjs_close(value instanceId)
{
    close(val_int(instanceId));
}
DEFINE_PRIM(sockjs_close, 1);

#endif


extern "C" {
    void sockjs_main () {
	   val_int(0); // Fix Neko init
    }
	
}
DEFINE_ENTRY_POINT (sockjs_main);



extern "C" int sockjs_register_prims () { return 0; }