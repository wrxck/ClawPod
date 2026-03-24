/*
 * OCMediaPipeline.m
 * ClawPod - Media Processing Implementation
 */

#import "MediaPipeline.h"

#pragma mark - Image Operations

@implementation OCImageOps

+ (UIImage *)resizeImage:(UIImage *)image maxDimension:(CGFloat)maxDim {
    CGSize size = image.size;
    if (size.width <= maxDim && size.height <= maxDim) return image;

    CGFloat scale = MIN(maxDim / size.width, maxDim / size.height);
    CGSize newSize = CGSizeMake(size.width * scale, size.height * scale);

    UIGraphicsBeginImageContextWithOptions(newSize, NO, 1.0);
    [image drawInRect:CGRectMake(0, 0, newSize.width, newSize.height)];
    UIImage *resized = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return resized;
}

+ (NSData *)compressImage:(UIImage *)image quality:(CGFloat)quality {
    return UIImageJPEGRepresentation(image, quality);
}

+ (CGSize)imageSizeAtPath:(NSString *)path {
    UIImage *img = [UIImage imageWithContentsOfFile:path];
    return img ? img.size : CGSizeZero;
}

+ (NSData *)imageToPNG:(UIImage *)image { return UIImagePNGRepresentation(image); }
+ (NSData *)imageToJPEG:(UIImage *)image quality:(CGFloat)q { return UIImageJPEGRepresentation(image, q); }

@end

#pragma mark - TTS Service

@implementation OCTTSService

- (void)dealloc { [_apiKey release]; [_voiceId release]; [_model release]; [super dealloc]; }

- (void)synthesize:(NSString *)text
        completion:(void(^)(NSData *, NSString *, NSError *))completion {
    switch (_provider) {
        case OCTTSProviderElevenLabs:
            [self _synthesizeElevenLabs:text completion:completion];
            break;
        case OCTTSProviderOpenAI:
            [self _synthesizeOpenAI:text completion:completion];
            break;
        default:
            completion(nil, nil, [NSError errorWithDomain:@"OCTTS" code:-1
                userInfo:@{NSLocalizedDescriptionKey: @"System TTS not available on iOS 6"}]);
            break;
    }
}

- (void)_synthesizeElevenLabs:(NSString *)text
                   completion:(void(^)(NSData *, NSString *, NSError *))completion {
    NSString *voice = _voiceId ?: @"21m00Tcm4TlvDq8ikWAM"; /* Default Rachel */
    NSString *url = [NSString stringWithFormat:
        @"https://api.elevenlabs.io/v1/text-to-speech/%@", voice];
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [req setHTTPMethod:@"POST"];
    [req setValue:_apiKey forHTTPHeaderField:@"xi-api-key"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [req setValue:@"audio/mpeg" forHTTPHeaderField:@"Accept"];
    NSDictionary *body = @{@"text": text,
        @"model_id": _model ?: @"eleven_monolingual_v1"};
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
            completion(d, @"mp3", e);
        }];
}

- (void)_synthesizeOpenAI:(NSString *)text
               completion:(void(^)(NSData *, NSString *, NSError *))completion {
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:@"https://api.openai.com/v1/audio/speech"]];
    [req setHTTPMethod:@"POST"];
    [req setValue:[NSString stringWithFormat:@"Bearer %@", _apiKey] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    NSDictionary *body = @{@"model": @"tts-1", @"input": text,
        @"voice": _voiceId ?: @"alloy", @"response_format": @"mp3"};
    [req setHTTPBody:[NSJSONSerialization dataWithJSONObject:body options:0 error:nil]];

    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
            completion(d, @"mp3", e);
        }];
}

@end

#pragma mark - Link Understanding

@implementation OCLinkUnderstanding

+ (void)extractContentFromURL:(NSString *)urlString
                    completion:(void(^)(NSString *, NSString *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) { completion(nil, nil, [NSError errorWithDomain:@"OCLink" code:-1
        userInfo:@{NSLocalizedDescriptionKey: @"Invalid URL"}]); return; }

    NSURLRequest *req = [NSURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:15];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
            if (e) { completion(nil, nil, e); return; }
            NSString *html = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
            if (!html) { completion(nil, @"[Binary content]", nil); return; }

            /* Extract title */
            NSString *title = [self _extractBetween:@"<title>" and:@"</title>" from:html];

            /* Extract main text - strip all HTML tags */
            NSMutableString *text = [[html mutableCopy] autorelease];
            /* Remove script/style blocks */
            [self _removeTag:@"script" from:text];
            [self _removeTag:@"style" from:text];
            /* Strip remaining tags */
            while (YES) {
                NSRange open = [text rangeOfString:@"<"];
                if (open.location == NSNotFound) break;
                NSRange close = [text rangeOfString:@">" options:0
                    range:NSMakeRange(open.location, [text length] - open.location)];
                if (close.location == NSNotFound) break;
                [text deleteCharactersInRange:NSMakeRange(open.location,
                    close.location - open.location + 1)];
            }
            /* Clean up whitespace */
            NSString *clean = [text stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceAndNewlineCharacterSet]];
            /* Truncate to 8KB */
            if ([clean length] > 8192) clean = [clean substringToIndex:8192];
            completion(title, clean, nil);
        }];
}

+ (void)fetchMetadata:(NSString *)urlString
           completion:(void(^)(NSDictionary *, NSError *))completion {
    NSURL *url = [NSURL URLWithString:urlString];
    NSURLRequest *req = [NSURLRequest requestWithURL:url
        cachePolicy:NSURLRequestReloadIgnoringCacheData timeoutInterval:10];
    [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
        completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
            if (e) { completion(nil, e); return; }
            NSString *html = [[[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] autorelease];
            NSMutableDictionary *meta = [NSMutableDictionary dictionary];
            /* OpenGraph tags */
            NSString *ogTitle = [self _extractOGProperty:@"og:title" from:html];
            NSString *ogDesc = [self _extractOGProperty:@"og:description" from:html];
            NSString *ogImage = [self _extractOGProperty:@"og:image" from:html];
            if (ogTitle) [meta setObject:ogTitle forKey:@"title"];
            if (ogDesc) [meta setObject:ogDesc forKey:@"description"];
            if (ogImage) [meta setObject:ogImage forKey:@"image"];
            completion(meta, nil);
        }];
}

+ (NSString *)_extractBetween:(NSString *)start and:(NSString *)end from:(NSString *)html {
    NSRange s = [html rangeOfString:start options:NSCaseInsensitiveSearch];
    if (s.location == NSNotFound) return nil;
    NSRange e = [html rangeOfString:end options:NSCaseInsensitiveSearch
        range:NSMakeRange(s.location + s.length, [html length] - s.location - s.length)];
    if (e.location == NSNotFound) return nil;
    return [html substringWithRange:NSMakeRange(s.location + s.length,
        e.location - s.location - s.length)];
}

+ (NSString *)_extractOGProperty:(NSString *)prop from:(NSString *)html {
    NSString *search = [NSString stringWithFormat:@"property=\"%@\" content=\"", prop];
    NSRange r = [html rangeOfString:search options:NSCaseInsensitiveSearch];
    if (r.location == NSNotFound) return nil;
    NSUInteger start = r.location + r.length;
    NSRange end = [html rangeOfString:@"\"" options:0
        range:NSMakeRange(start, MIN([html length] - start, 500))];
    if (end.location == NSNotFound) return nil;
    return [html substringWithRange:NSMakeRange(start, end.location - start)];
}

+ (void)_removeTag:(NSString *)tag from:(NSMutableString *)html {
    NSString *open = [NSString stringWithFormat:@"<%@", tag];
    NSString *close = [NSString stringWithFormat:@"</%@>", tag];
    while (YES) {
        NSRange o = [html rangeOfString:open options:NSCaseInsensitiveSearch];
        if (o.location == NSNotFound) break;
        NSRange c = [html rangeOfString:close options:NSCaseInsensitiveSearch
            range:NSMakeRange(o.location, [html length] - o.location)];
        NSUInteger end = c.location != NSNotFound ? c.location + c.length : [html length];
        [html deleteCharactersInRange:NSMakeRange(o.location, end - o.location)];
    }
}

@end

#pragma mark - Transcription Service

@implementation OCTranscriptionService
- (void)dealloc { [_apiKey release]; [_provider release]; [super dealloc]; }

- (void)transcribe:(NSData *)audioData format:(NSString *)format
        completion:(void(^)(NSString *, NSError *))completion {
    if ([_provider isEqualToString:@"openai"]) {
        /* OpenAI Whisper API */
        NSString *url = @"https://api.openai.com/v1/audio/transcriptions";
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
        [req setHTTPMethod:@"POST"];
        [req setValue:[NSString stringWithFormat:@"Bearer %@", _apiKey] forHTTPHeaderField:@"Authorization"];

        /* Multipart form data */
        NSString *boundary = @"OCBoundary12345";
        [req setValue:[NSString stringWithFormat:@"multipart/form-data; boundary=%@", boundary]
             forHTTPHeaderField:@"Content-Type"];

        NSMutableData *body = [NSMutableData data];
        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nwhisper-1\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:[[NSString stringWithFormat:@"--%@\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.%@\"\r\nContent-Type: audio/%@\r\n\r\n", boundary, format ?: @"wav", format ?: @"wav"] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:audioData];
        [body appendData:[[NSString stringWithFormat:@"\r\n--%@--\r\n", boundary] dataUsingEncoding:NSUTF8StringEncoding]];
        [req setHTTPBody:body];

        [NSURLConnection sendAsynchronousRequest:req queue:[NSOperationQueue mainQueue]
            completionHandler:^(NSURLResponse *r, NSData *d, NSError *e) {
                if (e) { completion(nil, e); return; }
                NSDictionary *result = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
                completion([result objectForKey:@"text"], nil);
            }];
    } else {
        completion(nil, [NSError errorWithDomain:@"OCTranscription" code:-1
            userInfo:@{NSLocalizedDescriptionKey: @"Unsupported transcription provider"}]);
    }
}
@end

#pragma mark - WebChat HTML Server

@implementation OCWebChatServer

+ (NSString *)webChatHTMLForGatewayHost:(NSString *)host port:(uint16_t)port {
    return [NSString stringWithFormat:@
        "<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>ClawPod Chat</title>"
        "<style>"
        "* { margin:0; padding:0; box-sizing:border-box; }"
        "body { font-family:-apple-system,Helvetica,sans-serif; background:#1a1a2e; color:#eee; height:100vh; display:flex; flex-direction:column; }"
        "#header { padding:12px; background:#16213e; text-align:center; font-size:18px; font-weight:bold; }"
        "#messages { flex:1; overflow-y:auto; padding:12px; }"
        ".msg { margin:6px 0; max-width:80%%; padding:10px 14px; border-radius:18px; word-wrap:break-word; }"
        ".user { background:#0a84ff; margin-left:auto; color:#fff; }"
        ".assistant { background:#2a2a4a; color:#e0e0e0; }"
        "#input-bar { display:flex; padding:8px; background:#16213e; gap:8px; }"
        "#input { flex:1; padding:10px; border-radius:20px; border:1px solid #333; background:#1a1a2e; color:#eee; font-size:16px; outline:none; }"
        "#send { padding:10px 20px; border-radius:20px; border:none; background:#0a84ff; color:#fff; font-size:16px; cursor:pointer; }"
        "#status { padding:4px 12px; font-size:11px; color:#888; background:#111; text-align:center; }"
        "</style></head><body>"
        "<div id='header'>ClawPod</div>"
        "<div id='status'>Connecting...</div>"
        "<div id='messages'></div>"
        "<div id='input-bar'><input id='input' placeholder='Message...' autocomplete='off'/>"
        "<button id='send' onclick='send()'>Send</button></div>"
        "<script>"
        "var ws,sid,reqId=0,streamBuf='';"
        "function connect(){"
        "ws=new WebSocket('ws://%@:%d/');"
        "ws.onopen=function(){document.getElementById('status').textContent='Connected';ws.send(JSON.stringify({type:'req',id:'c1',method:'connect',params:{minProtocol:3,maxProtocol:3,client:{id:'webchat',displayName:'WebChat',version:'1.0',platform:'browser',mode:'frontend'},auth:{},role:'operator',scopes:['operator.admin']}}));};"
        "ws.onmessage=function(e){var f=JSON.parse(e.data);"
        "if(f.type==='res'&&f.payload&&f.payload.type==='hello-ok'){document.getElementById('status').textContent='Authenticated';listSessions();}"
        "if(f.type==='event'&&(f.event==='chat.event'||f.event==='sessions.message')){var p=f.payload;if(p.state==='delta'&&p.message){streamBuf+=p.message.content||'';updateStream();}else if(p.state==='final'){if(p.message&&p.message.content)streamBuf=p.message.content;finalizeStream();}}"
        "if(f.type==='res'&&f.payload&&f.payload.sessions){var s=f.payload.sessions;if(s.length>0)sid=s[0].key;}"
        "};"
        "ws.onclose=function(){document.getElementById('status').textContent='Disconnected';setTimeout(connect,3000);};"
        "}"
        "function listSessions(){ws.send(JSON.stringify({type:'req',id:'ls'+(++reqId),method:'sessions.list',params:{}}));}"
        "function send(){var i=document.getElementById('input');var t=i.value.trim();if(!t)return;i.value='';"
        "if(!sid){ws.send(JSON.stringify({type:'req',id:'cs'+(++reqId),method:'sessions.create',params:{displayName:'WebChat'}}));setTimeout(function(){send2(t);},500);return;}"
        "send2(t);}"
        "function send2(t){addMsg(t,'user');streamBuf='';addMsg('...','assistant');ws.send(JSON.stringify({type:'req',id:'m'+(++reqId),method:'sessions.send',params:{key:sid,message:t}}));}"
        "function addMsg(t,r){var d=document.getElementById('messages');var m=document.createElement('div');m.className='msg '+r;m.textContent=t;d.appendChild(m);d.scrollTop=d.scrollHeight;}"
        "function updateStream(){var msgs=document.querySelectorAll('.msg.assistant');var last=msgs[msgs.length-1];if(last)last.textContent=streamBuf||'...';document.getElementById('messages').scrollTop=document.getElementById('messages').scrollHeight;}"
        "function finalizeStream(){var msgs=document.querySelectorAll('.msg.assistant');var last=msgs[msgs.length-1];if(last)last.textContent=streamBuf;streamBuf='';document.getElementById('messages').scrollTop=document.getElementById('messages').scrollHeight;}"
        "document.getElementById('input').onkeypress=function(e){if(e.key==='Enter')send();};"
        "connect();"
        "</script></body></html>", host, port];
}

+ (NSString *)controlUIHTMLForGatewayHost:(NSString *)host port:(uint16_t)port {
    return [NSString stringWithFormat:@
        "<!DOCTYPE html><html><head><meta charset='utf-8'>"
        "<meta name='viewport' content='width=device-width,initial-scale=1'>"
        "<title>ClawPod Control</title>"
        "<style>"
        "body{font-family:-apple-system,sans-serif;background:#111;color:#eee;padding:20px;}"
        "h1{color:#0a84ff;margin-bottom:20px;}h2{color:#888;margin:20px 0 10px;}"
        ".card{background:#1a1a2e;border-radius:12px;padding:16px;margin:8px 0;}"
        ".stat{display:inline-block;margin:8px 16px 8px 0;}"
        ".stat .val{font-size:24px;font-weight:bold;color:#0a84ff;}"
        ".stat .lbl{font-size:12px;color:#888;}"
        "table{width:100%%;border-collapse:collapse;}td,th{padding:8px;text-align:left;border-bottom:1px solid #333;}"
        ".online{color:#4ade80;}.offline{color:#f87171;}"
        "button{padding:8px 16px;border-radius:8px;border:none;background:#0a84ff;color:#fff;cursor:pointer;margin:4px;}"
        "</style></head><body>"
        "<h1>ClawPod Control Panel</h1>"
        "<div class='card' id='health'>Loading...</div>"
        "<h2>Sessions</h2><div class='card' id='sessions'>Loading...</div>"
        "<h2>Channels</h2><div class='card' id='channels'>Loading...</div>"
        "<h2>Tools</h2><div class='card' id='tools'>Loading...</div>"
        "<script>"
        "function api(path,cb){fetch('http://%@:%d'+path).then(r=>r.json()).then(cb).catch(e=>console.error(e));}"
        "api('/health',function(d){"
        "document.getElementById('health').innerHTML="
        "'<div class=\"stat\"><div class=\"val\">'+d.uptime+'s</div><div class=\"lbl\">Uptime</div></div>'"
        "+'<div class=\"stat\"><div class=\"val\">'+d.connectedClients+'</div><div class=\"lbl\">Clients</div></div>'"
        "+'<div class=\"stat\"><div class=\"val\">'+d.activeSessions+'</div><div class=\"lbl\">Sessions</div></div>'"
        "+'<div class=\"stat\"><div class=\"val\">'+(d.memoryMB||'?')+'MB</div><div class=\"lbl\">Memory</div></div>';"
        "});"
        "api('/api/sessions',function(d){var h='<table><tr><th>Key</th><th>Name</th><th>Status</th></tr>';d.sessions.forEach(function(s){h+='<tr><td>'+s.key.substring(0,8)+'...</td><td>'+s.displayName+'</td><td>'+s.status+'</td></tr>';});h+='</table>';document.getElementById('sessions').innerHTML=h;});"
        "</script></body></html>", host, port];
}

@end
