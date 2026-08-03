import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await [
    Permission.location,
    Permission.locationWhenInUse,
    Permission.locationAlways,
    Permission.camera,
    Permission.storage,
  ].request();

  runApp(const THHKConnectApp());
}

class THHKConnectApp extends StatelessWidget {
  const THHKConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'THHK Connect',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F172A),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  InAppWebViewController? webViewController;
  double _progress = 0;
  StreamSubscription<Position>? _positionStream;

  final String baseUrl = "https://thhkconnect.vercel.app/";

  final InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: true,
    javaScriptEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    geolocationEnabled: true,
    allowFileAccessFromFileURLs: true,
    allowUniversalAccessFromFileURLs: true,
    allowContentAccess: true,
    useOnDownloadStart: true,
    useHybridComposition: true,
    supportZoom: false,
    mixedContentMode: MixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
    thirdPartyCookiesEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    mediaPlaybackRequiresUserGesture: false,
    useShouldOverrideUrlLoading: true,
  );

  @override
  void initState() {
    super.initState();
    _startLocationUpdates();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  // =====================================================================
  // GPS Location Stream
  // =====================================================================
  Future<void> _startLocationUpdates() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }
    if (permission == LocationPermission.deniedForever) return;

    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2,
    );

    _positionStream = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) => _injectLocationToWeb(position),
      onError: (error) => debugPrint("GPS Stream error: $error"),
    );

    try {
      Position initialPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      _injectLocationToWeb(initialPosition);
    } catch (e) {
      debugPrint("Initial position error: $e");
    }
  }

  void _injectLocationToWeb(Position position) {
    if (webViewController == null) return;

    final locationMap = {
      "lat": position.latitude,
      "lon": position.longitude,
      "latitude": position.latitude,
      "longitude": position.longitude,
      "accuracy": position.accuracy,
      "isMock": position.isMocked,
      "is_mock": position.isMocked,
    };
    final jsonString = jsonEncode(locationMap);

    final jsCode = '''
      (function() {
        var locData = '$jsonString';
        window.Android = window.Android || {};
        window.Android.getNativeLocation = function() { return locData; };
        window.Android.getLocation = function() { return locData; };
        window.Android.getDeviceId = function() { return 'FLUTTER_ANDROID_NATIVE'; };
        
        if (navigator.geolocation) {
          navigator.geolocation.getCurrentPosition = function(success, error, options) {
            if (success) {
              success({
                coords: {
                  latitude: ${position.latitude},
                  longitude: ${position.longitude},
                  accuracy: ${position.accuracy},
                  altitude: null, altitudeAccuracy: null, heading: null, speed: null
                },
                timestamp: Date.now()
              });
            }
          };
        }
      })();
    ''';

    webViewController?.evaluateJavascript(source: jsCode);
  }

  // =====================================================================
  // Native File Upload Handler
  // =====================================================================
  Future<dynamic> _handleNativeUpload(List<dynamic> args) async {
    try {
      final String base64Data = args[0] as String;
      final String uploadUrl = args[1] as String;
      final String contentType = args[2] as String;
      final String uploadToken = args[3] as String;

      debugPrint("[NativeUpload] URL: $uploadUrl");
      debugPrint("[NativeUpload] ContentType: $contentType, base64Len: ${base64Data.length}");

      final bytes = base64Decode(base64Data);
      debugPrint("[NativeUpload] Decoded ${bytes.length} bytes");

      final httpClient = HttpClient();
      httpClient.connectionTimeout = const Duration(seconds: 30);
      
      final request = await httpClient.postUrl(Uri.parse(uploadUrl));
      request.headers.set('Content-Type', contentType);
      request.headers.set('X-Upload-Token', uploadToken);
      request.contentLength = bytes.length;
      request.add(bytes);

      final response = await request.close();
      final responseBody = await response.transform(utf8.decoder).join();
      httpClient.close();

      debugPrint("[NativeUpload] Status: ${response.statusCode}, Body: $responseBody");

      return jsonEncode({
        'ok': response.statusCode >= 200 && response.statusCode < 300,
        'status': response.statusCode,
        'body': responseBody,
      });
    } catch (e, stack) {
      debugPrint("[NativeUpload] ERROR: $e\n$stack");
      return jsonEncode({
        'ok': false,
        'status': 0,
        'body': jsonEncode({'success': false, 'error': e.toString()}),
      });
    }
  }

  // =====================================================================
  // Inject JavaScript: pre-cache file + fetch override
  // 
  // Strategi:
  // 1. Saat user memilih file via <input type="file">, LANGSUNG baca
  //    ke base64 via FileReader dan simpan di window._fileDataCache.
  //    Ini dilakukan SEGERA setelah file dipilih (saat FileReader masih
  //    punya akses ke content:// URI).
  // 2. Saat fetch() ke workers.dev/upload dipanggil, gunakan data
  //    dari cache (bukan mencoba membaca ulang File/Blob yang mungkin
  //    sudah expired di WebView Android).
  // 3. Fallback: coba body.arrayBuffer() jika cache kosong.
  // =====================================================================
  void _injectUploadHelper(InAppWebViewController controller) {
    const js = r'''
(function() {
  if (window._nativeUploadV3) return;
  window._nativeUploadV3 = true;
  
  // ============ BAGIAN 1: Pre-cache file saat dipilih ============
  window._fileDataCache = {};
  
  // Intercept semua <input type="file"> change events
  document.addEventListener('change', function(evt) {
    var el = evt.target;
    if (!el || el.tagName !== 'INPUT' || el.type !== 'file') return;
    if (!el.files || el.files.length === 0) return;
    
    var file = el.files[0];
    var inputId = el.id || el.name || 'file_' + Date.now();
    
    console.log('[FileCache] File selected: ' + file.name + ' (' + file.size + 'b) from input#' + inputId);
    
    // Baca file SEGERA ke base64 — ini harus dilakukan di event handler
    // saat content:// URI masih valid
    var reader = new FileReader();
    reader.onload = function() {
      var b64 = reader.result.split(',')[1] || '';
      window._fileDataCache[inputId] = {
        base64: b64,
        type: file.type || 'application/octet-stream',
        name: file.name,
        size: file.size
      };
      // Juga simpan sebagai "latest" untuk fallback
      window._fileDataCache['_latest'] = window._fileDataCache[inputId];
      console.log('[FileCache] Cached OK: ' + file.name + ', b64 len=' + b64.length);
    };
    reader.onerror = function() {
      console.error('[FileCache] FileReader FAILED for ' + file.name);
      
      // Fallback: coba via URL.createObjectURL + canvas
      // (URL.createObjectURL biasanya berhasil di WebView meski FileReader gagal)
      try {
        var blobUrl = URL.createObjectURL(file);
        var img = new Image();
        img.onload = function() {
          var canvas = document.createElement('canvas');
          canvas.width = img.naturalWidth;
          canvas.height = img.naturalHeight;
          // Batasi ukuran max 1200px
          var maxDim = 1200;
          if (canvas.width > maxDim || canvas.height > maxDim) {
            var ratio = Math.min(maxDim / canvas.width, maxDim / canvas.height);
            canvas.width = Math.round(canvas.width * ratio);
            canvas.height = Math.round(canvas.height * ratio);
          }
          var ctx = canvas.getContext('2d');
          ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
          URL.revokeObjectURL(blobUrl);
          
          var dataUrl = canvas.toDataURL('image/jpeg', 0.8);
          var b64 = dataUrl.split(',')[1] || '';
          window._fileDataCache[inputId] = {
            base64: b64,
            type: 'image/jpeg',
            name: file.name,
            size: b64.length
          };
          window._fileDataCache['_latest'] = window._fileDataCache[inputId];
          console.log('[FileCache] Canvas fallback OK, b64 len=' + b64.length);
        };
        img.onerror = function() {
          URL.revokeObjectURL(blobUrl);
          console.error('[FileCache] Canvas fallback also failed');
        };
        img.src = blobUrl;
      } catch(e2) {
        console.error('[FileCache] All fallbacks failed:', e2);
      }
    };
    reader.readAsDataURL(file);
  }, true);  // useCapture=true untuk menangkap sebelum handler lain
  
  // ============ BAGIAN 2: Override fetch untuk upload ============
  var _origFetch = window.fetch;
  
  window.fetch = function(url, options) {
    if (typeof url === 'string'
        && url.indexOf('workers.dev/upload') !== -1
        && options
        && options.method === 'POST'
        && options.body) {
      
      console.log('[NativeUpload] Intercepting POST to: ' + url);
      
      var body = options.body;
      
      // Ekstrak headers
      var contentType = '';
      var uploadToken = '';
      if (options.headers) {
        if (typeof options.headers.get === 'function') {
          contentType = options.headers.get('Content-Type') || '';
          uploadToken = options.headers.get('X-Upload-Token') || '';
        } else {
          contentType = options.headers['Content-Type'] || options.headers['content-type'] || '';
          uploadToken = options.headers['X-Upload-Token'] || options.headers['x-upload-token'] || '';
        }
      }
      
      return new Promise(function(resolve, reject) {
        
        function sendViaDart(base64, ct) {
          if (!ct) ct = contentType || 'application/octet-stream';
          console.log('[NativeUpload] -> Dart, b64 len=' + base64.length + ', ct=' + ct);
          
          window.flutter_inappwebview.callHandler('nativeUpload', base64, url, ct, uploadToken)
            .then(function(raw) {
              console.log('[NativeUpload] <- Dart response OK');
              var r = JSON.parse(raw);
              resolve(new Response(r.body, {
                status: r.status || 200,
                statusText: r.ok ? 'OK' : 'Error',
                headers: {'Content-Type': 'application/json'}
              }));
            })
            .catch(function(err) {
              console.error('[NativeUpload] Dart error:', err);
              reject(new TypeError('Upload gagal: ' + err));
            });
        }
        
        function ab2b64(buf) {
          var u8 = new Uint8Array(buf);
          var chunks = [];
          var chunkSize = 8192;
          for (var i = 0; i < u8.length; i += chunkSize) {
            var slice = u8.subarray(i, Math.min(i + chunkSize, u8.length));
            var binStr = '';
            for (var j = 0; j < slice.length; j++) binStr += String.fromCharCode(slice[j]);
            chunks.push(binStr);
          }
          return btoa(chunks.join(''));
        }
        
        // === STRATEGI 1: Gunakan pre-cached data ===
        var cached = window._fileDataCache['_latest'];
        if (cached && cached.base64 && cached.base64.length > 0) {
          console.log('[NativeUpload] Using pre-cached file data (' + cached.name + ')');
          sendViaDart(cached.base64, cached.type || contentType);
          // Clear cache setelah dipakai
          window._fileDataCache = {};
          return;
        }
        
        console.log('[NativeUpload] No cache, trying to read body directly');
        
        // === STRATEGI 2: body.arrayBuffer() (Promise API) ===
        if (typeof body.arrayBuffer === 'function') {
          console.log('[NativeUpload] Trying body.arrayBuffer()');
          body.arrayBuffer()
            .then(function(ab) {
              console.log('[NativeUpload] arrayBuffer OK, size=' + ab.byteLength);
              sendViaDart(ab2b64(ab), contentType || (body.type || 'application/octet-stream'));
            })
            .catch(function(e1) {
              console.error('[NativeUpload] arrayBuffer failed:', e1);
              
              // === STRATEGI 3: FileReader ===
              if (body instanceof Blob) {
                console.log('[NativeUpload] Trying FileReader fallback');
                var reader = new FileReader();
                reader.onload = function() {
                  var b64 = reader.result.split(',')[1] || '';
                  sendViaDart(b64, contentType || body.type);
                };
                reader.onerror = function() {
                  console.error('[NativeUpload] FileReader also failed');
                  reject(new TypeError('Gagal membaca file untuk upload'));
                };
                reader.readAsDataURL(body);
              } else {
                reject(new TypeError('Gagal membaca file untuk upload'));
              }
            });
          return;
        }
        
        // === STRATEGI 4: Blob via FileReader ===
        if (body instanceof Blob) {
          var reader = new FileReader();
          reader.onload = function() {
            var b64 = reader.result.split(',')[1] || '';
            sendViaDart(b64, contentType || body.type);
          };
          reader.onerror = function() {
            reject(new TypeError('Gagal membaca file untuk upload'));
          };
          reader.readAsDataURL(body);
          return;
        }
        
        // === STRATEGI 5: ArrayBuffer langsung ===
        if (body instanceof ArrayBuffer) {
          sendViaDart(ab2b64(body), contentType);
          return;
        }
        if (ArrayBuffer.isView(body)) {
          sendViaDart(ab2b64(body.buffer), contentType);
          return;
        }
        
        // Fallback total
        console.warn('[NativeUpload] All strategies failed, using original fetch');
        _origFetch.call(window, url, options).then(resolve).catch(reject);
      });
    }
    
    return _origFetch.call(this, url, options);
  };
  
  console.log('[NativeUpload] v3 installed: file pre-cache + multi-strategy fetch override');
})();
    ''';

    controller.evaluateJavascript(source: js);
  }

  // =====================================================================
  // Widget Build
  // =====================================================================
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (webViewController != null && await webViewController!.canGoBack()) {
          webViewController!.goBack();
        } else {
          if (!context.mounted) return;
          final shouldPop = await _showExitDialog(context);
          if (shouldPop && context.mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: SafeArea(
          child: Column(
            children: [
              if (_progress < 1.0)
                LinearProgressIndicator(
                  value: _progress,
                  color: Colors.amber,
                  backgroundColor: Colors.transparent,
                  minHeight: 3,
                ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(url: WebUri(baseUrl)),
                  initialSettings: settings,
                  onWebViewCreated: (controller) {
                    webViewController = controller;

                    // Register native upload handler
                    controller.addJavaScriptHandler(
                      handlerName: 'nativeUpload',
                      callback: (args) => _handleNativeUpload(args),
                    );
                  },
                  onLoadStop: (controller, url) {
                    // Re-inject GPS location
                    Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
                    ).then((pos) => _injectLocationToWeb(pos)).catchError((_) {});

                    // Inject file pre-cache + fetch override
                    _injectUploadHelper(controller);
                  },
                  onProgressChanged: (controller, progress) {
                    setState(() {
                      _progress = progress / 100.0;
                    });
                  },
                  onGeolocationPermissionsShowPrompt: (controller, origin) async {
                    var status = await Permission.location.status;
                    if (!status.isGranted) {
                      status = await Permission.location.request();
                    }
                    return GeolocationPermissionShowPromptResponse(
                      origin: origin, allow: true, retain: true,
                    );
                  },
                  onPermissionRequest: (controller, request) async {
                    return PermissionResponse(
                      resources: request.resources,
                      action: PermissionResponseAction.GRANT,
                    );
                  },
                  shouldOverrideUrlLoading: (controller, navigationAction) async {
                    return NavigationActionPolicy.ALLOW;
                  },
                  onConsoleMessage: (controller, consoleMessage) {
                    debugPrint("JS: ${consoleMessage.message}");
                  },
                  onReceivedHttpError: (controller, request, response) {
                    debugPrint("HTTP ${response.statusCode}: ${request.url}");
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<bool> _showExitDialog(BuildContext context) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Keluar Aplikasi?'),
            content: const Text('Apakah Anda yakin ingin keluar dari THHK Connect?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Keluar'),
              ),
            ],
          ),
        ) ??
        false;
  }
}
