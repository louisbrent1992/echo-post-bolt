import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

class InstagramOAuthDialog extends StatefulWidget {
  final String authUrl;
  final String redirectUri;
  final String state;

  const InstagramOAuthDialog({
    Key? key,
    required this.authUrl,
    required this.redirectUri,
    required this.state,
  }) : super(key: key);

  @override
  State<InstagramOAuthDialog> createState() => _InstagramOAuthDialogState();
}

class _InstagramOAuthDialogState extends State<InstagramOAuthDialog> {
  late WebViewController _controller;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
            });
          },
          onNavigationRequest: (NavigationRequest request) {
            // Check if the URL is our redirect URI
            if (request.url.startsWith(widget.redirectUri)) {
              final uri = Uri.parse(request.url);
              final code = uri.queryParameters['code'];
              final error = uri.queryParameters['error'];
              final returnedState = uri.queryParameters['state'];

              if (kDebugMode) {
                print('📷 Instagram OAuth callback received:');
                print('  URL: ${request.url}');
                print('  Code: $code');
                print('  Error: $error');
                print('  State: $returnedState');
              }

              // Validate state parameter
              if (returnedState != widget.state) {
                setState(() {
                  _error = 'State parameter mismatch';
                });
                return NavigationDecision.prevent;
              }

              // Handle error response
              if (error != null) {
                setState(() {
                  _error = 'Instagram authorization failed: $error';
                });
                return NavigationDecision.prevent;
              }

              // Handle success response
              if (code != null) {
                Navigator.of(context).pop(code);
                return NavigationDecision.prevent;
              }

              setState(() {
                _error = 'No authorization code received';
              });
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (WebResourceError error) {
            if (kDebugMode) {
              print('❌ WebView error: ${error.description}');
            }
            setState(() {
              _error = 'WebView error: ${error.description}';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.authUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                border: Border(
                  bottom: BorderSide(color: Colors.grey[300]!),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.camera_alt, color: Colors.purple),
                  const SizedBox(width: 8),
                  Expanded(
                    child: const Text(
                      'Instagram Authorization',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // WebView
            Expanded(
              child: Stack(
                children: [
                  WebViewWidget(controller: _controller),
                  if (_isLoading)
                    const Center(
                      child: CircularProgressIndicator(),
                    ),
                  if (_error != null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red[200]!),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.error, color: Colors.red),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.red),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: () {
                                setState(() {
                                  _error = null;
                                });
                                _controller.reload();
                              },
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
