import 'dart:collection';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:openim_enterprise_chat/src/common/apis.dart';
import 'package:openim_enterprise_chat/src/res/strings.dart';
import 'package:openim_enterprise_chat/src/widgets/titlebar.dart';

import 'workbench_js_handler.dart';
/*

class WorkbenchPage extends StatelessWidget {
  final logic = Get.find<WorkbenchLogic>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: EnterpriseTitleBar.leftTitle(
        title: StrRes.workbench,
      ),
      backgroundColor: PageStyle.c_FFFFFF,
      body: Column(
        children: [],
      ),
    );
  }
}
*/

class WorkbenchPage extends StatefulWidget {
  @override
  _InAppWebViewExampleScreenState createState() =>
      new _InAppWebViewExampleScreenState();
}

class _InAppWebViewExampleScreenState extends State<WorkbenchPage> {
  final GlobalKey webViewKey = GlobalKey();
  late OpenIMJsHandler jsHandler;

  InAppWebViewController? webViewController;
  InAppWebViewGroupOptions options = InAppWebViewGroupOptions(
      crossPlatform: InAppWebViewOptions(
          useShouldOverrideUrlLoading: true,
          mediaPlaybackRequiresUserGesture: false),
      android: AndroidInAppWebViewOptions(
        useHybridComposition: true,
      ),
      ios: IOSInAppWebViewOptions(
        allowsInlineMediaPlayback: true,
      ));

  late PullToRefreshController pullToRefreshController;
  String url = "";
  double progress = 0;

  @override
  void initState() {
    super.initState();
    Apis.getClientConfig().then((value) {
      url = value['discoverPageURL'];
      webViewController?.loadUrl(urlRequest: URLRequest(url: Uri.parse(url)));
    });

    pullToRefreshController = PullToRefreshController(
      options: PullToRefreshOptions(
        color: Colors.blue,
      ),
      onRefresh: () async {
        if (Platform.isAndroid) {
          webViewController?.reload();
        } else if (Platform.isIOS) {
          webViewController?.loadUrl(
              urlRequest: URLRequest(url: await webViewController?.getUrl()));
        }
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: EnterpriseTitleBar.leftTitle(
          title: StrRes.workbench,
        ),
        body: SafeArea(
            child: Column(children: <Widget>[
          Expanded(
            child: Stack(
              children: [
                InAppWebView(
                  key: webViewKey,
                  // contextMenu: contextMenu,
                  // initialUrlRequest: URLRequest(
                  initialUrlRequest: URLRequest(url: Uri.parse(url)),
                  // initialFile: "assets/html/index.html",
                  initialData: InAppWebViewInitialData(data: """
<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, minimum-scale=1.0">
    </head>
    <body>
        <h1>????????????</h1>
        <script>
            window.addEventListener("flutterInAppWebViewPlatformReady", function(event) {
                  window.flutter_inappwebview.callHandler('getLoginCertificate').then(function(result) {
                    // print to the console the data coming
                    // from the Flutter side.
                    console.log(JSON.stringify(result));
                    document.getElementById("loginCertificate").innerHTML = JSON.stringify(result);
             });
            });

            function getDeviceInfo(){
              window.flutter_inappwebview.callHandler('getDeviceInfo')
                  .then(function(result) {
                    // print to the console the data coming
                    // from the Flutter side.
                    document.getElementById("deviceInfo").innerHTML = JSON.stringify(result);
                    console.log(JSON.stringify(result));
                });
            }

            function getLoginUserInfo(){
              window.flutter_inappwebview.callHandler('getLoginUserInfo')
                  .then(function(result) {
                    // print to the console the data coming
                    // from the Flutter side.
                    document.getElementById("loginUserInfo").innerHTML = JSON.stringify(result);
                    console.log(JSON.stringify(result));
                });
            }

            function createGroupChat(){
               console.log('????????????');
               window.flutter_inappwebview.callHandler('createGroupChat');
            }

            function selectOrganizationMember(){
               console.log('????????????');
               window.flutter_inappwebview.callHandler('selectOrganizationMember').then(function(result) {
                    // print to the console the data coming
                    // from the Flutter side.
                    document.getElementById("members").innerHTML = JSON.stringify(result);
                    console.log(JSON.stringify(result));
               });
            }

            function viewUserInfo(){
              var userID = document.getElementById("userID0").value;
              window.flutter_inappwebview.callHandler('viewUserInfo',{'userID':userID});
            }

            function toChat(){
              var userID = document.getElementById("userID1").value;
              window.flutter_inappwebview.callHandler('getUserInfo',userID).then(function(result) {
                    // print to the console the data coming
                    // from the Flutter side.
                   // console.log(result[0].nickname);
                   // console.log(JSON.stringify(result));
                   var userID = result[0].userID;
                   var nickname = result[0].nickname;
                   var faceURL = result[0].faceURL;
                   window.flutter_inappwebview.callHandler('toChat',{'userID':userID,'nickname':nickname,'faceURL':faceURL,'sessionType':1});
              });
            }

            function selectFile(input){
              //??????????????????????????? ????????????????????????????????????files??????????????????<img>??? src??????
             var file = input.files[0];
             //??????????????????????????????FileReader
             if(window.FileReader){
              //???????????????????????????
              var fr = new FileReader();
              //????????????????????????????????????????????? ????????????????????????file
              //??????????????????????????????file???????????????files????????????
              //??????????????????????????????data:URL?????????????????????base64??????????????????fr?????????result???
              fr.readAsDataURL(file);
              fr.onloadend = function(){
               document.getElementById("image").src = fr.result;
              }
             }
           }

           function openPhotoSheet(){
              window.flutter_inappwebview.callHandler('openPhotoSheet').then(function(result) {
                    // print to the console the data coming
                    // from the Flutter side.
                    console.log(JSON.stringify(result));
                    console.log(result.path);
                    console.log(result.url);
                    document.getElementById("avatar").src = 'file:///'+ result.path;
             });
           }

           function showDialog(){
             window.flutter_inappwebview.callHandler('showDialog',{'title':'???????????????','rightBtnText':'??????','leftBtnText':'??????'});
           }

        </script>
        ???????????????<div id="loginCertificate"></div>
        <button onclick="getDeviceInfo()">??????????????????</button>
        <div id="deviceInfo"></div>
        </br>
         <button onclick="getLoginUserInfo()">????????????????????????</button>
        <div id="loginUserInfo"></div>
        </br>
        <button onclick="createGroupChat()">????????????</button>
        </br>
        <button onclick="selectOrganizationMember()">???????????????</button>
        <div id="members"></div>
        </br>
        ??????ID: <input id="userID0" type="text" value="1153408799"><button onclick="viewUserInfo()">????????????</button>
        </br>
        ??????ID: <input id="userID1" type="text" value="1153408799"><button onclick="toChat()">?????????</button>
        </br>
        <input id="file" type="file" onchange="selectFile(this)"/>
        <img id="image" width="100" height="100"/>
        </br>
        <button onclick="openPhotoSheet()">????????????</button>
        <img id="avatar" width="100" height="100"/>
        <button onclick="showDialog()">???????????????</button>
    </body>
</html>
                      """),
                  initialUserScripts: UnmodifiableListView<UserScript>([]),
                  initialOptions: options,
                  pullToRefreshController: pullToRefreshController,
                  onWebViewCreated: (controller) {
                    webViewController = controller;
                    jsHandler = OpenIMJsHandler(controller);
                    jsHandler.register();
                  },
                  onLoadStart: (controller, url) {},
                  androidOnPermissionRequest:
                      (controller, origin, resources) async {
                    return PermissionRequestResponse(
                        resources: resources,
                        action: PermissionRequestResponseAction.GRANT);
                  },
                  shouldOverrideUrlLoading:
                      (controller, navigationAction) async {
                    var uri = navigationAction.request.url!;

                    // if (![
                    //   "http",
                    //   "https",
                    //   "file",
                    //   "chrome",
                    //   "data",
                    //   "javascript",
                    //   "about"
                    // ].contains(uri.scheme)) {
                    //   if (await canLaunch(url)) {
                    //     // Launch the App
                    //     await launch(
                    //       url,
                    //     );
                    //     // and cancel the request
                    //     return NavigationActionPolicy.CANCEL;
                    //   }
                    // }

                    return NavigationActionPolicy.ALLOW;
                  },
                  onLoadStop: (controller, url) async {
                    pullToRefreshController.endRefreshing();
                  },
                  onLoadError: (controller, url, code, message) {
                    pullToRefreshController.endRefreshing();
                  },
                  onProgressChanged: (controller, progress) {
                    if (progress == 100) {
                      pullToRefreshController.endRefreshing();
                    }
                    setState(() {
                      this.progress = progress / 100;
                    });
                  },
                  onUpdateVisitedHistory: (controller, url, androidIsReload) {},
                  onConsoleMessage: (controller, consoleMessage) {
                    print('==webview======$consoleMessage');
                  },
                ),
                progress < 1.0
                    ? LinearProgressIndicator(value: progress)
                    : Container(),
              ],
            ),
          ),
        ])));
  }
}
