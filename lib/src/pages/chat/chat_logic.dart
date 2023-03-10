import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:common_utils/common_utils.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_openim_widget/flutter_openim_widget.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get/get.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mime_type/mime_type.dart';
import 'package:openim_enterprise_chat/src/common/apis.dart';
import 'package:openim_enterprise_chat/src/common/config.dart';
import 'package:openim_enterprise_chat/src/core/controller/app_controller.dart';
import 'package:openim_enterprise_chat/src/core/controller/cache_controller.dart';
import 'package:openim_enterprise_chat/src/core/controller/im_controller.dart';
import 'package:openim_enterprise_chat/src/models/contacts_info.dart';
import 'package:openim_enterprise_chat/src/pages/conversation/conversation_logic.dart';
import 'package:openim_enterprise_chat/src/pages/select_contacts/select_contacts_logic.dart';
import 'package:openim_enterprise_chat/src/res/strings.dart';
import 'package:openim_enterprise_chat/src/routes/app_navigator.dart';
import 'package:openim_enterprise_chat/src/sdk_extension/message_manager.dart';
import 'package:openim_enterprise_chat/src/utils/data_persistence.dart';
import 'package:openim_enterprise_chat/src/utils/im_util.dart';
import 'package:openim_enterprise_chat/src/widgets/bottom_sheet_view.dart';
import 'package:openim_enterprise_chat/src/widgets/custom_dialog.dart';
import 'package:openim_enterprise_chat/src/widgets/im_widget.dart';
import 'package:openim_enterprise_chat/src/widgets/loading_view.dart';
import 'package:pull_to_refresh/pull_to_refresh.dart';
import 'package:rxdart/rxdart.dart' as rx;
import 'package:uri_to_file/uri_to_file.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_compress/video_compress.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';

import 'group_setup/group_member_manager/member_list/member_list_logic.dart';

class ChatLogic extends GetxController {
  final imLogic = Get.find<IMController>();
  final appLogic = Get.find<AppController>();
  final conversationLogic = Get.find<ConversationLogic>();
  final cacheLogic = Get.find<CacheController>();
  final inputCtrl = TextEditingController();
  final focusNode = FocusNode();
  final scrollController = ScrollController();

  final refreshController = RefreshController();

  /// Click on the message to process voice playback, video playback, picture preview, etc.
  final clickSubject = rx.PublishSubject<int>();

  ///
  final forceCloseToolbox = rx.PublishSubject<bool>();

  ///
  final forceCloseMenuSub = rx.PublishSubject<bool>();

  /// The status of message sending,
  /// there are two kinds of success or failure, true success, false failure
  final msgSendStatusSubject = rx.PublishSubject<MsgStreamEv<bool>>();

  /// The progress of sending messages, such as the progress of uploading pictures, videos, and files
  final msgSendProgressSubject = rx.PublishSubject<MsgStreamEv<int>>();

  /// Download progress of pictures, videos, and files
  // final downloadProgressSubject = rx.PublishSubject<MsgStreamEv<double>>();

  bool get isSingleChat => null != uid && uid!.trim().isNotEmpty;

  bool get isGroupChat => null != gid && gid!.trim().isNotEmpty;

  String? uid;
  String? gid;
  var name = ''.obs;
  var icon = ''.obs;
  var messageList = <Message>[].obs;
  var lastTime;
  Timer? typingTimer;
  var typing = false.obs;
  var intervalSendTypingMsg = IntervalDo();
  Message? quoteMsg;
  var quoteContent = "".obs;
  var multiSelMode = false.obs;
  var multiSelList = <Message>[].obs;
  var _borderRadius = BorderRadius.only(
    topLeft: Radius.circular(30),
    topRight: Radius.circular(30),
  );

  var atUserNameMappingMap = <String, String>{};
  var atUserInfoMappingMap = <String, UserInfo>{};
  var curMsgAtUser = <String>[];

  var _isFirstLoad = true;
  var _lastCursorIndex = -1;
  var onlineStatus = false.obs;
  var onlineStatusDesc = ''.obs;
  Timer? onlineStatusTimer;

  final unreadMsgCount = 0.obs;

  var favoriteList = <String>[].obs;

  var scaleFactor = Config.textScaleFactor.obs;
  var background = "".obs;

  ///  ?????????????????????????????????
  var memberUpdateInfoMap = <String, GroupMembersInfo>{};

  /// ????????????????????????????????????
  var groupMessageReadMembers = <String, List<String>>{};

  /// ???????????????
  var groupMutedStatus = 0.obs;

  /// ???????????????
  var groupMemberRoleLevel = 1.obs;

  /// ?????????????????????
  var muteEndTime = 0.obs;
  GroupInfo? groupInfo;
  GroupMembersInfo? groupMembersInfo;
  // sdk???isNotInGroup?????????
  final isValidChat = false.obs;
  var memberCount = 0.obs;

  var privateMessageList = <Message>[];

  var isInBlacklist = false.obs;

  final _audioPlayer = AudioPlayer();
  var _currentPlayClientMsgID = "".obs;

  var isShowPopMenu = false.obs;
  final _showMenuCacheMessageList = <Message>[];
  final _scrollingCacheMessageList = <Message>[];

  ConversationInfo? conversationInfo;
  var announcement = ''.obs;

  late StreamSubscription memberAddSub;
  late StreamSubscription joinedGroupAddedSub;
  late StreamSubscription joinedGroupDeletedSub;
  late StreamSubscription memberInfoChangedSub;
  late StreamSubscription groupInfoUpdatedSub;
  late StreamSubscription friendInfoChangedSub;

  // late StreamSubscription signalingMessageSub;

  /// super group
  int? lastMinSeq;
  final showCallingMember = false.obs;
  final participants = <Participant>[].obs;
  late RoomCallingInfo roomCallingInfo;

  /// ?????????????????????
  bool isCurrentChat(Message message) {
    var senderId = message.sendID;
    var receiverId = message.recvID;
    var groupId = message.groupID;
    // var sessionType = message.sessionType;
    var isCurSingleChat = message.isSingleChat &&
        isSingleChat &&
        (senderId == uid ||
            // ??????????????????????????????uid???????????????
            senderId == OpenIM.iMManager.uid && receiverId == uid);
    var isCurGroupChat = message.isGroupChat && isGroupChat && gid == groupId;
    return isCurSingleChat || isCurGroupChat;
  }

  void scrollBottom() {
    // ??????listview??????????????????
    // if (autoCtrl.offset != 0) {
    //   listViewKey.value = _uuid.v4();
    // }
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      scrollController.jumpTo(0);
    });
  }

  // Future scrollToBottom() async {
  //   WidgetsBinding.instance?.addPostFrameCallback((timeStamp) async {
  //     while (scrollController.position.pixels !=
  //         scrollController.position.maxScrollExtent) {
  //       scrollController.jumpTo(scrollController.position.maxScrollExtent);
  //       await SchedulerBinding.instance!.endOfFrame;
  //     }
  //   });
  // }

  @override
  void onReady() {
    _checkInBlacklist();
    queryGroupInfo();
    // queryMyGroupMemberInfo();
    getAtMappingMap();
    readDraftText();
    queryUserOnlineStatus();
    _resetGroupAtType();
    super.onReady();
  }

  @override
  void onInit() {
    var arguments = Get.arguments;
    uid = arguments['uid'];
    gid = arguments['gid'];
    name.value = arguments['name'];
    isValidChat.value = isSingleChat;
    conversationInfo = arguments['conversationInfo'];
    if (null != arguments['icon']) icon.value = arguments['icon'];
    // cacheLogic.initFavoriteEmoji();
    _initChatConfig();
    _initPlayListener();
    _getUnreadMsgCount();

    // ??????????????????
    // _startQueryOnlineStatus();
    // ??????????????????
    imLogic.onRecvNewMessage = (Message message) {
      // ??????????????????????????????
      if (isCurrentChat(message)) {
        // ????????????????????????
        if (message.contentType == MessageType.typing) {
          if (message.content == 'yes') {
            // ??????????????????
            if (null == typingTimer) {
              typing.value = true;
              typingTimer = Timer.periodic(Duration(seconds: 2), (timer) {
                // ????????????????????????
                typing.value = false;
                typingTimer?.cancel();
                typingTimer = null;
              });
            }
          } else {
            // ??????????????????
            typing.value = false;
            typingTimer?.cancel();
            typingTimer = null;
          }
        } else {
          if (!messageList.contains(message)) {
            _parseAnnouncement(message);
            if (isShowPopMenu.value) {
              _showMenuCacheMessageList.add(message);
            } else {
              // final keep = scrollController.offset == 0;
              // messageList.add(message);
              // if (keep) {
              //   scrollBottom();
              // }
              if (scrollController.offset == 0) {
                messageList.add(message);
                scrollBottom();
              } else {
                _scrollingCacheMessageList.add(message);
              }
            }

            // ios ????????????????????????????????????
            // messageList.sort((a, b) {
            //   if (a.sendTime! > b.sendTime!) {
            //     return 1;
            //   } else if (a.sendTime! > b.sendTime!) {
            //     return -1;
            //   } else {
            //     return 0;
            //   }
            // });
          }
        }
      } else {
        if (message.contentType != MessageType.typing) {
          unreadMsgCount.value++;
        }
      }
    };
    // ????????????????????????
    imLogic.onRecvMessageRevoked = (String msgId) {
      messageList.removeWhere((e) => e.clientMsgID == msgId);
    };
    // ???????????????????????????????????????
    imLogic.onRecvMessageRevokedV2 = (RevokedInfo info) {
      // messageList.removeWhere((e) => e.clientMsgID == msgId);
      var msg = messageList.firstWhereOrNull((e) => e.clientMsgID == info.clientMsgID);
      msg?.content = jsonEncode(info);
      msg?.contentType = MessageType.advancedRevoke;
      messageList.refresh();
    };
    // ????????????????????????
    imLogic.onRecvC2CReadReceipt = (List<ReadReceiptInfo> list) {
      try {
        // var info = list.firstWhere((read) => read.uid == uid);
        list.forEach((readInfo) {
          if (readInfo.userID == uid) {
            messageList.forEach((e) {
              if (readInfo.msgIDList?.contains(e.clientMsgID) == true) {
                e.isRead = true;
                e.hasReadTime = _timestamp;
                // e.hasReadTime = readInfo.readTime;
                // e.attachedInfoElem!.hasReadTime = readInfo.readTime;
              }
            });
            messageList.refresh();
          }
        });
      } catch (e) {}
    };
    // ????????????????????????
    imLogic.onRecvGroupReadReceipt = (List<ReadReceiptInfo> list) {
      try {
        list.forEach((readInfo) {
          if (readInfo.groupID == gid) {
            messageList.forEach((e) {
              var uidList = e.attachedInfoElem?.groupHasReadInfo?.hasReadUserIDList;
              if (null != uidList &&
                  !uidList.contains(readInfo.userID!) &&
                  (readInfo.msgIDList?.contains(e.clientMsgID) == true)) {
                uidList.add(readInfo.userID!);
              }
            });
          }
        });
        messageList.refresh();
      } catch (e) {}
    };
    // ??????????????????
    imLogic.onMsgSendProgress = (String msgId, int progress) {
      msgSendProgressSubject.addSafely(
        MsgStreamEv<int>(msgId: msgId, value: progress),
      );
    };

    joinedGroupAddedSub = imLogic.joinedGroupAddedSubject.stream.listen((event) {
      if (event.groupID == gid) {
        isValidChat.value = true;
      }
    });

    joinedGroupDeletedSub = imLogic.joinedGroupDeletedSubject.stream.listen((event) {
      if (event.groupID == gid) {
        isValidChat.value = false;
      }
    });

    // ??????????????????
    memberAddSub = imLogic.memberAddedSubject.stream.listen((info) {
      var groupId = info.groupID;
      if (groupId == gid) {
        _putMemberInfo([info]);
      }
    });

    // ??????????????????
    memberInfoChangedSub = imLogic.memberInfoChangedSubject.listen((info) {
      var groupId = info.groupID;
      if (groupId == gid) {
        if (info.userID == OpenIM.iMManager.uid) {
          muteEndTime.value = info.muteEndTime ?? 0;
          groupMemberRoleLevel.value = info.roleLevel ?? GroupRoleLevel.member;
          _mutedClearAllInput();
        }
        _putMemberInfo([info]);
      }
    });

    // ???????????????????????????
    clickSubject.listen((index) {
      print('index:$index');
      parseClickEvent(indexOfMessage(index, calculate: false));
    });

    // ???????????????
    inputCtrl.addListener(() {
      intervalSendTypingMsg.run(
        fuc: () => sendTypingMsg(focus: true),
        milliseconds: 2000,
      );
      clearCurAtMap();
      _updateDartText(createDraftText());
    });

    // ???????????????
    focusNode.addListener(() {
      _lastCursorIndex = inputCtrl.selection.start;
      focusNodeChanged(focusNode.hasFocus);
    });

    // ???????????????
    groupInfoUpdatedSub = imLogic.groupInfoUpdatedSubject.listen((value) {
      if (gid == value.groupID) {
        name.value = value.groupName ?? '';
        icon.value = value.faceURL ?? '';
        groupMutedStatus.value = value.status ?? 0;
        memberCount.value = value.memberCount ?? 0;
        _mutedClearAllInput();
      }
    });

    // ??????????????????
    friendInfoChangedSub = imLogic.friendInfoChangedSubject.listen((value) {
      if (uid == value.userID) {
        name.value = value.getShowName();
        icon.value = value.faceURL ?? '';
      }
    });

    imLogic.roomParticipantConnectedSubject.listen((value) {
      if (value.groupID == gid) {
        roomCallingInfo = value;
        participants.assignAll(value.participant ?? []);
      }
    });
    imLogic.roomParticipantDisconnectedSubject.listen((value) {
      if (value.groupID == gid) {
        roomCallingInfo = value;
        participants.assignAll(value.participant ?? []);
      }
    });
    // signalingMessageSub = imLogic.signalingMessageSubject.listen((value) {
    //   print('====value.userID:${value.userID}===uid: $uid == gid:$gid');
    //   if (value.isSingleChat && value.userID == uid ||
    //       value.isGroupChat && value.groupID == gid) {
    //     messageList.add(value.message);
    //     scrollBottom();
    //   }
    // });

    // imLogic.conversationChangedSubject.listen((newList) {
    //   for (var newValue in newList) {
    //     if (newValue.conversationID == info?.conversationID) {
    //       burnAfterReading.value = newValue.isPrivateChat!;
    //       break;
    //     }
    //   }
    // });
    super.onInit();
  }

  // ?????????????????????
  void _getUnreadMsgCount() {
    OpenIM.iMManager.conversationManager.getTotalUnreadMsgCount().then((count) {
      unreadMsgCount.value = int.tryParse(count) ?? 0;
    });
  }

  void chatSetup() {
    if (null != uid && uid!.isNotEmpty) {
      AppNavigator.startChatSetup(
        uid: uid!,
        name: name.value,
        icon: icon.value,
      );
    } else if (null != gid && gid!.isNotEmpty) {
      // ok = 0 blocked = 1 Dismissed = 2 Muted  = 3
      AppNavigator.startGroupSetup(
        gid: gid!,
        name: name.value,
        icon: icon.value,
      );
    }
  }

  void clearCurAtMap() {
    curMsgAtUser.removeWhere((uid) => !inputCtrl.text.contains('@$uid '));
  }

  // ??????id/??????????????????
  // ???????????????????????????id???name
  void getAtMappingMap() async {
    // if (isGroupChat) {
    //   var list = await OpenIM.iMManager.groupManager.getGroupMemberList(
    //     groupId: gid!,
    //   );
    //
    //   _putMemberInfo(list);
    // }
  }

  /// ?????????????????????
  void _putMemberInfo(List<GroupMembersInfo>? list) {
    list?.forEach((member) {
      _setAtMapping(
        userID: member.userID!,
        nickname: member.nickname!,
        faceURL: member.faceURL,
      );
      memberUpdateInfoMap[member.userID!] = member;
    });
    // ?????????????????????
    messageList.refresh();
    atUserNameMappingMap[OpenIM.iMManager.uid] = StrRes.you;
    atUserInfoMappingMap[OpenIM.iMManager.uid] = OpenIM.iMManager.uInfo;

    DataPersistence.putAtUserMap(gid!, atUserNameMappingMap);
  }

  bool get _isSuperGroup => conversationInfo?.conversationType == ConversationType.superGroup;

  /// ????????????????????????
  Future<bool> getHistoryMsgList() async {
    late List<Message> list;
    if (_isSuperGroup) {
      final result = await OpenIM.iMManager.messageManager.getAdvancedHistoryMessageList(
        // userID: uid,
        // groupID: gid,
        conversationID: conversationInfo?.conversationID,
        count: 30,
        startMsg: _isFirstLoad ? null : messageList.first,
        lastMinSeq: lastMinSeq,
      );
      if (result.messageList == null) return false;
      list = result.messageList!;
      lastMinSeq = result.lastMinSeq;
    } else {
      list = await OpenIM.iMManager.messageManager.getHistoryMessageList(
        // userID: uid,
        // groupID: gid,
        conversationID: conversationInfo?.conversationID,
        count: 30,
        startMsg: _isFirstLoad ? null : messageList.first,
      );
    }

    if (_isFirstLoad) {
      _isFirstLoad = false;
      messageList..assignAll(list);
      scrollBottom();
    } else {
      messageList.insertAll(0, list);
    }
    return list.length == 30;
  }

  /// ???????????????????????????????????????????????????????????????@??????
  void sendTextMsg() async {
    var content = inputCtrl.text;
    if (content.isEmpty) return;
    var message;
    if (curMsgAtUser.isNotEmpty) {
      // ?????? @ ??????
      message = await OpenIM.iMManager.messageManager.createTextAtMessage(
        text: content,
        atUserIDList: curMsgAtUser,
        atUserInfoList: curMsgAtUser
            .map((e) => AtUserInfo(
                  atUserID: e,
                  groupNickname: atUserNameMappingMap[e],
                ))
            .toList(),
        quoteMessage: quoteMsg,
      );
    } else if (quoteMsg != null) {
      // ??????????????????
      message = await OpenIM.iMManager.messageManager.createQuoteMessage(
        text: content,
        quoteMsg: quoteMsg!,
      );
    } else {
      // ??????????????????
      message = await OpenIM.iMManager.messageManager.createTextMessage(
        text: content,
      );
    }
    _sendMessage(message);
  }

  /// ????????????
  void sendPicture({required String path}) async {
    var message = await OpenIM.iMManager.messageManager.createImageMessageFromFullPath(
      imagePath: path,
    );
    _sendMessage(message);
  }

  /// ????????????
  void sendVoice({required int duration, required String path}) async {
    var message = await OpenIM.iMManager.messageManager.createSoundMessageFromFullPath(
      soundPath: path,
      duration: duration,
    );
    _sendMessage(message);
  }

  ///  ????????????
  void sendVideo({
    required String videoPath,
    required String mimeType,
    required int duration,
    required String thumbnailPath,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createVideoMessageFromFullPath(
      videoPath: videoPath,
      videoType: mimeType,
      duration: duration,
      snapshotPath: thumbnailPath,
    );
    _sendMessage(message);
  }

  /// ????????????
  void sendFile({required String filePath, required String fileName}) async {
    var message = await OpenIM.iMManager.messageManager.createFileMessageFromFullPath(
      filePath: filePath,
      fileName: fileName,
    );
    _sendMessage(message);
  }

  /// ????????????
  void sendLocation({
    required dynamic location,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createLocationMessage(
      latitude: location['latitude'],
      longitude: location['longitude'],
      description: location['description'],
    );
    _sendMessage(message);
  }

  /// ??????
  void sendForwardMsg(
    Message originalMessage, {
    String? userId,
    String? groupId,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createForwardMessage(
      message: originalMessage,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  /// ????????????
  void sendMergeMsg({
    String? userId,
    String? groupId,
  }) async {
    var summaryList = <String>[];
    var title;
    for (var msg in multiSelList) {
      summaryList.add('${msg.senderNickname}???${IMUtil.parseMsg(msg, replaceIdToNickname: true)}');
      if (summaryList.length >= 2) break;
    }
    if (isGroupChat) {
      title = "??????${StrRes.chatRecord}";
    } else {
      var partner1 = OpenIM.iMManager.uInfo.getShowName();
      var partner2 = name.value;
      title = "$partner1???$partner2${StrRes.chatRecord}";
    }
    var message = await OpenIM.iMManager.messageManager.createMergerMessage(
      messageList: multiSelList,
      title: title,
      summaryList: summaryList,
    );
    _sendMessage(message, userId: userId, groupId: groupId);
  }

  /// ????????????????????????
  void sendTypingMsg({bool focus = false}) async {
    if (isSingleChat) {
      OpenIM.iMManager.messageManager.typingStatusUpdate(
        userID: uid!,
        msgTip: focus ? 'yes' : 'no',
      );
    }
  }

  /// ????????????
  void sendCarte({required String uid, String? name, String? icon}) async {
    var message = await OpenIM.iMManager.messageManager.createCardMessage(
      data: {"userID": uid, 'nickname': name, 'faceURL': icon},
    );
    _sendMessage(message);
  }

  /// ?????????????????????
  void sendCustomMsg({
    required String data,
    required String extension,
    required String description,
  }) async {
    var message = await OpenIM.iMManager.messageManager.createCustomMessage(
      data: data,
      extension: extension,
      description: description,
    );
    _sendMessage(message);
  }

  void _sendMessage(
    Message message, {
    String? userId,
    String? groupId,
    bool addToUI = true,
  }) {
    log('send : ${json.encode(message)}');
    // null == userId && null == groupId || userId == uid --> ??????????????????
    if (null == userId && null == groupId || userId == uid) {
      if (addToUI) {
        // ??????????????????????????????ui
        messageList.add(message);
        scrollBottom();
      }
    }
    print('uid:$uid  userId:$userId  gid:$gid    groupId:$groupId');
    _reset(message);
    // ????????????????????????????????????????????????????????????????????????????????????????????????
    bool useOuterValue = null != userId || null != groupId;
    OpenIM.iMManager.messageManager
        .sendMessage(
          message: message,
          userID: useOuterValue ? userId : uid,
          groupID: useOuterValue ? groupId : gid,
          offlinePushInfo: OfflinePushInfo(
            title: "????????????????????????",
            desc: "????????????????????????",
            iOSBadgeCount: true,
            iOSPushSound: '+1',
          ),
        )
        .then((value) => _sendSucceeded(message, value))
        .catchError((e) => _senFailed(message, e))
        .whenComplete(() => _completed());
  }

  ///  ??????????????????
  void _sendSucceeded(Message oldMsg, Message newMsg) {
    print('message send success----');
    // message.status = MessageStatus.succeeded;
    oldMsg.update(newMsg);
    msgSendStatusSubject.addSafely(MsgStreamEv<bool>(
      msgId: oldMsg.clientMsgID!,
      value: true,
    ));
  }

  ///  ??????????????????
  void _senFailed(Message message, e) async {
    print('message send failed e :$e');
    message.status = MessageStatus.failed;
    msgSendStatusSubject.addSafely(MsgStreamEv<bool>(
      msgId: message.clientMsgID!,
      value: false,
    ));
    if (e is PlatformException && isSingleChat) {
      int? customType;
      if (e.code == MessageFailedCode.blockedByFriend.toString()) {
        customType = CustomMessageType.blockedByFriend;
      } else if (e.code == MessageFailedCode.deletedByFriend.toString()) {
        customType = CustomMessageType.deletedByFriend;
      }
      if (null != customType) {
        final hintMessage = (await OpenIM.iMManager.messageManager.createFailedHintMessage(
          type: customType,
        ))
          ..status = 2
          ..isRead = true;
        messageList.add(hintMessage);
        OpenIM.iMManager.messageManager.insertSingleMessageToLocalStorage(
          message: hintMessage,
          receiverID: uid,
          senderID: OpenIM.iMManager.uid,
        );
      }
    }
  }

  void _reset(Message message) {
    if (message.contentType == MessageType.text ||
        message.contentType == MessageType.at_text ||
        message.contentType == MessageType.quote) {
      inputCtrl.clear();
      setQuoteMsg(null);
    }
    closeMultiSelMode();
  }

  /// todo
  void _completed() {
    messageList.refresh();
    // setQuoteMsg(-1);
    // closeMultiSelMode();
    // inputCtrl.clear();
  }

  /// ???????????????????????????
  void setQuoteMsg(Message? message) {
    if (message == null) {
      quoteMsg = null;
      quoteContent.value = '';
    } else {
      quoteMsg = message;
      var name = quoteMsg!.senderNickname;
      quoteContent.value = "$name???${IMUtil.parseMsg(quoteMsg!)}";
      focusNode.requestFocus();
    }
  }

  /// ????????????
  void deleteMsg(Message message) async {
    _deleteMessage(message);
  }

  /// ????????????
  void _deleteMultiMsg() {
    multiSelList.forEach((e) {
      _deleteMessage(e);
    });
    closeMultiSelMode();
  }

  _deleteMessage(Message message) async {
    try {
      await OpenIM.iMManager.messageManager
          .deleteMessageFromLocalAndSvr(
            message: message,
          )
          .then((value) => privateMessageList.remove(message))
          .then((value) => messageList.remove(message));
    } catch (e) {
      await OpenIM.iMManager.messageManager
          .deleteMessageFromLocalStorage(
            message: message,
          )
          .then((value) => privateMessageList.remove(message))
          .then((value) => messageList.remove(message));
    }
  }

  /// ????????????
  void revokeMsg(Message message) async {
    await OpenIM.iMManager.messageManager.revokeMessage(
      message: message,
    );
    message.contentType = MessageType.revoke;
    messageList.refresh();
  }

  /// ??????
  void forward(Message message) async {
    // IMWidget.showToast('????????????????????????!');
    var result = await AppNavigator.startSelectContacts(
      action: SelAction.FORWARD,
    );
    if (null != result) {
      sendForwardMsg(
        message,
        userId: result['userID'],
        groupId: result['groupID'],
      );
    }
  }

  /// ??????1000??????????????????
  /// ??????????????????????????????????????????
  void markMessageAsRead(Message message, bool visible) async {
    if (visible && message.contentType! < 1000 && message.contentType! != MessageType.voice) {
      var data = IMUtil.parseCustomMessage(message);
      if (null != data && data['viewType'] == CustomMessageType.call) {
        return;
      }
      if (isSingleChat) {
        _markC2CMessageAsRead(message);
      } else {
        _markGroupMessageAsRead(message);
      }
    }
  }

  /// ?????????????????????
  _markC2CMessageAsRead(Message message) async {
    if (!message.isRead! && message.sendID != OpenIM.iMManager.uid) {
      print('mark as read???${message.clientMsgID!} ${message.isRead}');
      // ??????????????????
      try {
        await OpenIM.iMManager.messageManager.markC2CMessageAsRead(
          userID: uid!,
          messageIDList: [message.clientMsgID!],
        );
      } catch (_) {}
      message.isRead = true;
      message.hasReadTime = _timestamp;
      messageList.refresh();
      // message.attachedInfoElem!.hasReadTime = _timestamp;
    }
  }

  /// ?????????????????????
  _markGroupMessageAsRead(Message message) async {
    if (!message.isRead! && message.sendID != OpenIM.iMManager.uid) {
      print('mark as read???${message.clientMsgID!} ${message.isRead} ${message.content}');
      // ??????????????????
      try {
        await OpenIM.iMManager.messageManager.markGroupMessageAsRead(
          groupID: gid!,
          messageIDList: [message.clientMsgID!],
        );
      } catch (_) {}
      message.isRead = true;
      message.hasReadTime = _timestamp;
      messageList.refresh();
      // message.attachedInfoElem!.hasReadTime = _timestamp;
    }
  }

  /// ????????????
  void mergeForward() {
    // IMWidget.showToast('????????????????????????!');
    Get.bottomSheet(
      BottomSheetView(
        items: [
          SheetItem(
            label: StrRes.mergeForward,
            borderRadius: _borderRadius,
            onTap: () async {
              var result = await AppNavigator.startSelectContacts(
                action: SelAction.FORWARD,
              );
              if (null != result) {
                sendMergeMsg(
                  userId: result['userID'],
                  groupId: result['groupID'],
                );
              }
            },
          ),
        ],
      ),
      barrierColor: Colors.transparent,
    );
  }

  /// ????????????
  void mergeDelete() {
    Get.bottomSheet(
      BottomSheetView(items: [
        SheetItem(
          label: StrRes.delete,
          borderRadius: _borderRadius,
          onTap: _deleteMultiMsg,
        ),
      ]),
      barrierColor: Colors.transparent,
    );
  }

  void multiSelMsg(Message message, bool checked) {
    if (checked) {
      // ????????????????????????
      if (multiSelList.length >= 20) {
        Get.dialog(CustomDialog(
          title: StrRes.forwardMaxCountTips,
        ));
      } else {
        multiSelList.add(message);
        multiSelList.sort((a, b) {
          if (a.createTime! > b.createTime!) {
            return 1;
          } else if (a.createTime! < b.createTime!) {
            return -1;
          } else {
            return 0;
          }
        });
      }
    } else {
      multiSelList.remove(message);
    }
  }

  void openMultiSelMode(Message message) {
    multiSelMode.value = true;
    multiSelMsg(message, true);
  }

  void closeMultiSelMode() {
    multiSelMode.value = false;
    multiSelList.clear();
  }

  /// ???????????????????????????????????????
  void closeToolbox() {
    forceCloseToolbox.addSafely(true);
  }

  /// ????????????
  void onTapLocation() async {
    var location = await Get.to(ChatWebViewMap());
    print(location);
    if (null != location) {
      sendLocation(location: location);
    }
  }

  /// ????????????
  void onTapAlbum() async {
    final List<AssetEntity>? assets = await AssetPicker.pickAssets(
      Get.context!,
    );
    if (null != assets) {
      for (var asset in assets) {
        _handleAssets(asset);
      }
    }
  }

  /// ????????????
  void onTapCamera() async {
    var resolutionPreset = ResolutionPreset.max;
    if (Platform.isAndroid) {
      final deviceInfo = appLogic.deviceInfo;
      if (deviceInfo is AndroidDeviceInfo && deviceInfo.brand.toLowerCase() == 'xiaomi') {
        resolutionPreset = ResolutionPreset.medium;
      }
    }
    final AssetEntity? entity = await CameraPicker.pickFromCamera(
      Get.context!,
      locale: Get.locale,
      pickerConfig: CameraPickerConfig(
        enableAudio: true,
        enableRecording: true,
        resolutionPreset: resolutionPreset,
      ),
    );
    _handleAssets(entity);
  }

  /// ???????????????????????????
  void onTapFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      // type: FileType.custom,
      // allowedExtensions: ['jpg', 'pdf', 'doc'],
    );

    if (result != null) {
      for (var file in result.files) {
        String? mimeType = mime(file.name);
        if (mimeType != null) {
          if (mimeType.contains('image/')) {
            sendPicture(path: file.path!);
            return;
          } else if (mimeType.contains('video/')) {
            try {
              final videoPath = file.path!;
              var mediaInfo = await VideoCompress.getMediaInfo(videoPath);
              var thumbnailFile = await VideoCompress.getFileThumbnail(
                videoPath,
                quality: 85,
              );
              sendVideo(
                videoPath: videoPath,
                mimeType: mimeType,
                duration: mediaInfo.duration?.toInt() ?? 0,
                thumbnailPath: thumbnailFile.path,
              );
              return;
            } catch (e) {}
          }
        }
        sendFile(filePath: file.path!, fileName: file.name);
      }
    } else {
      // User canceled the picker
    }
  }

  /// ??????
  void onTapCarte() async {
    var result = await AppNavigator.startSelectContacts(
      action: SelAction.CARTE,
    );
    if (null != result) {
      sendCarte(
        uid: result['userID'],
        name: result['nickname'],
        icon: result['faceURL'],
      );
    }
  }

  void _handleAssets(AssetEntity? asset) async {
    if (null != asset) {
      print('--------assets type-----${asset.type}');
      var path = (await asset.file)!.path;
      print('--------assets path-----$path');
      switch (asset.type) {
        case AssetType.image:
          sendPicture(path: path);
          break;
        case AssetType.video:
          var trulyW = asset.width;
          var trulyH = asset.height;
          var scaleW = 100.w;
          var scaleH = scaleW * trulyH / trulyW;
          var data = await asset.thumbnailDataWithSize(
            ThumbnailSize(scaleW.toInt(), scaleH.toInt()),
          );
          print('-----------video thumb build success----------------');
          final result = await ImageGallerySaver.saveImage(
            data!,
            isReturnImagePathOfIOS: true,
          );
          var thumbnailPath = result['filePath'];
          print('-----------gallery saver : ${json.encode(result)}---------');
          var filePrefix = 'file://';
          var uriPrefix = 'content://';
          if ('$thumbnailPath'.contains(filePrefix)) {
            thumbnailPath = thumbnailPath.substring(filePrefix.length);
          } else if ('$thumbnailPath'.contains(uriPrefix)) {
            // Uri uri = Uri.parse(thumbnailPath); // Parsing uri string to uri
            File file = await toFile(thumbnailPath);
            thumbnailPath = file.path;
          }
          sendVideo(
            videoPath: path,
            mimeType: asset.mimeType ?? CommonUtil.getMediaType(path) ?? '',
            duration: asset.duration,
            thumbnailPath: thumbnailPath,
          );
          // sendVoice(duration: asset.duration, path: path);
          break;
        default:
          break;
      }
    }
  }

  /// ????????????????????????
  void parseClickEvent(Message msg) async {
    log('parseClickEvent:${jsonEncode(msg)}');
    if (msg.contentType == MessageType.custom) {
      var data = msg.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      if (CustomMessageType.call == customType && !isInBlacklist.value) {
      } else if (CustomMessageType.meeting == customType) {
        var data = msg.customElem!.data;
        var map = json.decode(data!);
      }
      return;
    }
    if (msg.contentType == MessageType.voice) {
      _playVoiceMessage(msg);
      // ??????????????????
      if (isSingleChat) {
        _markC2CMessageAsRead(msg);
      } else {
        _markGroupMessageAsRead(msg);
      }
      return;
    }
    IMUtil.parseClickEvent(msg, messageList: messageList);
    // log("message:${json.encode(msg)}");
    // if (msg.contentType == MessageType.picture) {
    //   var list = messageList
    //       .where((p0) => p0.contentType == MessageType.picture)
    //       .toList();
    //   var index = list.indexOf(msg);
    //   if (index == -1) {
    //     IMUtil.openPicture([msg], index: 0, tag: msg.clientMsgID);
    //   } else {
    //     IMUtil.openPicture(list, index: index, tag: msg.clientMsgID);
    //   }
    // } else if (msg.contentType == MessageType.video) {
    //   IMUtil.openVideo(msg);
    // } else if (msg.contentType == MessageType.file) {
    //   IMUtil.openFile(msg);
    // } else if (msg.contentType == MessageType.card) {
    //   var info = ContactsInfo.fromJson(json.decode(msg.content!));
    //   AppNavigator.startFriendInfo(userInfo: info);
    // } else if (msg.contentType == MessageType.merger) {
    //   Get.to(
    //     () => PreviewMergeMsg(
    //       title: msg.mergeElem!.title!,
    //       messageList: msg.mergeElem!.multiMessage!,
    //     ),
    //     preventDuplicates: false,
    //   );
    // } else if (msg.contentType == MessageType.location) {
    //   var location = msg.locationElem;
    //   Map detail = json.decode(location!.description!);
    //   Get.to(() => MapView(
    //         latitude: location.latitude!,
    //         longitude: location.longitude!,
    //         addr1: detail['name'],
    //         addr2: detail['addr'],
    //       ));
    // }
  }

  /// ??????????????????
  void onTapQuoteMsg(Message message) {
    if (message.contentType == MessageType.quote) {
      parseClickEvent(message.quoteElem!.quoteMessage!);
    } else if (message.contentType == MessageType.at_text) {
      parseClickEvent(message.atElem!.quoteMessage!);
    }
  }

  /// ????????????????????????@??????
  void onLongPressLeftAvatar(Message message) {
    if (isMuted) return;
    if (isGroupChat) {
      // ????????????????????????
      _setAtMapping(
        userID: message.sendID!,
        nickname: message.senderNickname!,
        faceURL: message.senderFaceUrl,
      );
      var uid = message.sendID!;
      // var uname = msg.senderNickName;
      if (curMsgAtUser.contains(uid)) return;
      curMsgAtUser.add(uid);
      // ????????????????????????
      // ??????????????????????????????
      var cursor = inputCtrl.selection.base.offset;
      if (!focusNode.hasFocus) {
        focusNode.requestFocus();
        cursor = _lastCursorIndex;
      }
      if (cursor < 0) cursor = 0;
      print('========cursor:$cursor   _lastCursorIndex:$_lastCursorIndex');
      // ?????????????????????
      var start = inputCtrl.text.substring(0, cursor);
      print('===================start:$start');
      // ?????????????????????
      var end = inputCtrl.text.substring(cursor);
      print('===================end:$end');
      var at = ' @$uid ';
      inputCtrl.text = '$start$at$end';
      inputCtrl.selection = TextSelection.collapsed(offset: '$start$at'.length);
      // inputCtrl.selection = TextSelection.fromPosition(TextPosition(
      //   offset: '$start$at'.length,
      // ));
      _lastCursorIndex = inputCtrl.selection.start;
      print('$curMsgAtUser');
    }
  }

  void onTapLeftAvatar(Message message) {
    var info = ContactsInfo.fromJson({
      'userID': message.sendID!,
      'nickname': message.senderNickname,
      'faceURL': message.senderFaceUrl,
    });
    viewUserInfo(info);
    // AppNavigator.startFriendInfo(
    //   userInfo: info,
    //   showMuteFunction: havePermissionMute,
    //   groupID: gid!,
    // );
  }

  void clickAtText(id) async {
    var tag = await OpenIM.iMManager.conversationManager.getAtAllTag();
    if (id == tag) return;
    if (null != atUserInfoMappingMap[id]) {
      viewUserInfo(atUserInfoMappingMap[id]!);
      // AppNavigator.startFriendInfo(
      //   userInfo: atUserInfoMappingMap[id]!,
      //   showMuteFunction: havePermissionMute,
      //   groupID: gid!,
      // );
    } else {
      viewUserInfo(UserInfo(userID: id));
    }
  }

  void viewUserInfo(UserInfo info) {
    AppNavigator.startFriendInfo(
      userInfo: info,
      showMuteFunction: havePermissionMute,
      groupID: gid,
      offAllWhenDelFriend: isSingleChat,
    );
  }

  void clickLinkText(url, type) async {
    print('--------link  type:$type-------url: $url---');
    if (type == PatternType.AT) {
      clickAtText(url);
      return;
    }
    if (await canLaunch(url)) {
      await launch(url);
    }
    // await canLaunch(url) ? await launch(url) : throw 'Could not launch $url';
  }

  /// ????????????
  void readDraftText() {
    var draftText = Get.arguments['draftText'];
    print('readDraftText:$draftText');
    if (null != draftText && "" != draftText) {
      var map = json.decode(draftText!);
      String text = map['text'];
      // String? quoteMsgId = map['quoteMsgId'];
      Map<String, dynamic> atMap = map['at'];
      print('text:$text  atMap:$atMap');
      atMap.forEach((key, value) {
        if (!curMsgAtUser.contains(key)) curMsgAtUser.add(key);
        atUserNameMappingMap.putIfAbsent(key, () => value);
      });
      inputCtrl.text = text;
      inputCtrl.selection = TextSelection.fromPosition(TextPosition(
        offset: text.length,
      ));
      // if (null != quoteMsgId) {
      //   var index = messageList.indexOf(Message()..clientMsgID = quoteMsgId);
      //   print('quoteMsgId index:$index  length:${messageList.length}');
      //   setQuoteMsg(index);
      //   print('quoteMsgId index:$index  length:${messageList.length}');
      // }
      if (text.isNotEmpty) {
        focusNode.requestFocus();
      }
    }
  }

  /// ????????????draftText
  String createDraftText() {
    var atMap = <String, dynamic>{};
    curMsgAtUser.forEach((uid) {
      atMap[uid] = atUserNameMappingMap[uid];
    });
    if (inputCtrl.text.isEmpty) {
      return "";
    }
    return json.encode({
      'text': inputCtrl.text,
      'at': atMap,
      // 'quoteMsgId': quoteMsg?.clientMsgID,
    });
  }

  /// ?????????????????????
  exit() async {
    if (multiSelMode.value) {
      closeMultiSelMode();
      return false;
    }
    if (isShowPopMenu.value) {
      forceCloseMenuSub.add(true);
      return false;
    }
    Get.back(result: createDraftText());
    return true;
  }

  void _updateDartText(String text) {
    conversationLogic.updateDartText(
      text: text,
      conversationID: conversationInfo?.conversationID,
    );
  }

  void focusNodeChanged(bool hasFocus) {
    sendTypingMsg(focus: hasFocus);
    if (hasFocus) {
      print('focus:$hasFocus');
      scrollBottom();
    }
  }

  void copy(Message message) {
    IMUtil.copy(text: message.content!);
  }

  Message indexOfMessage(int index, {bool calculate = true}) => IMUtil.calChatTimeInterval(
        messageList,
        calculate: calculate,
      ).reversed.elementAt(index);

  ValueKey itemKey(Message message) => ValueKey(message.clientMsgID!);

  @override
  void onClose() {
    // inputCtrl.dispose();
    // focusNode.dispose();
    _audioPlayer.dispose();
    clickSubject.close();
    forceCloseToolbox.close();
    msgSendStatusSubject.close();
    msgSendProgressSubject.close();
    memberAddSub.cancel();
    memberInfoChangedSub.cancel();
    groupInfoUpdatedSub.cancel();
    friendInfoChangedSub.cancel();
    // signalingMessageSub?.cancel();
    forceCloseMenuSub.close();
    joinedGroupAddedSub.cancel();
    joinedGroupDeletedSub.cancel();
    // downloadProgressSubject.close();
    // onlineStatusTimer?.cancel();
    // destroyMsg();
    super.onClose();
  }

  String? getShowTime(Message message) {
    if (message.ext == true) {
      return IMUtil.getChatTimeline(message.sendTime!);
    }
    return null;
  }

  void clearAllMessage() {
    messageList.clear();
  }

  void onStartVoiceInput() {
    // SpeechToTextUtil.instance.startListening((result) {
    //   inputCtrl.text = result.recognizedWords;
    // });
  }

  void onStopVoiceInput() {
    // SpeechToTextUtil.instance.stopListening();
  }

  /// ????????????
  void onAddEmoji(String emoji) {
    var input = inputCtrl.text;
    if (_lastCursorIndex != -1 && input.isNotEmpty) {
      var part1 = input.substring(0, _lastCursorIndex);
      var part2 = input.substring(_lastCursorIndex);
      inputCtrl.text = '$part1$emoji$part2';
      _lastCursorIndex = _lastCursorIndex + emoji.length;
    } else {
      inputCtrl.text = '$input$emoji';
      _lastCursorIndex = emoji.length;
    }
    inputCtrl.selection = TextSelection.fromPosition(TextPosition(
      offset: _lastCursorIndex,
    ));
  }

  /// ????????????
  void onDeleteEmoji() {
    final input = inputCtrl.text;
    final regexEmoji =
        emojiFaces.keys.toList().join('|').replaceAll('[', '\\[').replaceAll(']', '\\]');
    final list = [regexAt, regexEmoji];
    final pattern = '(${list.toList().join('|')})';
    final atReg = RegExp(regexAt);
    final emojiReg = RegExp(regexEmoji);
    var reg = RegExp(pattern);
    var cursor = _lastCursorIndex;
    if (cursor == 0) return;
    Match? match;
    if (reg.hasMatch(input)) {
      for (var m in reg.allMatches(input)) {
        var matchText = m.group(0)!;
        var start = m.start;
        var end = start + matchText.length;
        if (end == cursor) {
          match = m;
          break;
        }
      }
    }
    var matchText = match?.group(0);
    if (matchText != null) {
      var start = match!.start;
      var end = start + matchText.length;
      if (atReg.hasMatch(matchText)) {
        String id = matchText.replaceFirst("@", "").trim();
        if (curMsgAtUser.remove(id)) {
          inputCtrl.text = input.replaceRange(start, end, '');
          cursor = start;
        } else {
          inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
          --cursor;
        }
      } else if (emojiReg.hasMatch(matchText)) {
        inputCtrl.text = input.replaceRange(start, end, "");
        cursor = start;
      } else {
        inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
        --cursor;
      }
    } else {
      inputCtrl.text = input.replaceRange(cursor - 1, cursor, '');
      --cursor;
    }
    _lastCursorIndex = cursor;
  }

  /// ??????????????????
  // void _getOnlineStatus(List<String> uidList) {
  //   Apis.queryOnlineStatus(
  //     uidList: uidList,
  //     onlineStatusCallback: (map) {
  //       onlineStatus.value = map[uidList.first]!;
  //     },
  //     onlineStatusDescCallback: (map) {
  //       onlineStatusDesc.value = map[uidList.first]!;
  //     },
  //   );
  // }

  // void _startQueryOnlineStatus() {
  //   if (null != uid && uid!.isNotEmpty && onlineStatusTimer == null) {
  //     _getOnlineStatus([uid!]);
  //     onlineStatusTimer = Timer.periodic(Duration(seconds: 5), (timer) {
  //       _getOnlineStatus([uid!]);
  //     });
  //   }
  // }

  String getSubTile() => typing.value ? StrRes.typing : onlineStatusDesc.value;

  bool showOnlineStatus() => !typing.value && onlineStatusDesc.isNotEmpty;

  /// ??????????????????????????????????????????
  bool enabledReadStatus(Message message) {
    try {
      // ????????????????????????
      if (message.contentType! > 1000 || message.contentType == 118) {
        return false;
      }
      switch (message.contentType) {
        case MessageType.custom:
          {
            var data = message.customElem!.data;
            var map = json.decode(data!);
            switch (map['customType']) {
              case CustomMessageType.call:
                return false;
            }
          }
      }
    } catch (e) {}
    return true;
  }

  bool isCallMessage(Message message) {
    switch (message.contentType) {
      case MessageType.custom:
        {
          var data = message.customElem!.data;
          var map = json.decode(data!);
          var customType = map['customType'];
          switch (customType) {
            case CustomMessageType.call:
              return true;
          }
        }
    }
    return false;
  }

  /// ?????????????????????@??????
  String? openAtList() {
    if (gid != null && gid!.isNotEmpty) {
      var cursor = inputCtrl.selection.baseOffset;
      AppNavigator.startGroupMemberList(
        gid: gid!,
        action: OpAction.AT,
      )?.then((memberList) {
        if (memberList is List<GroupMembersInfo>) {
          var buffer = StringBuffer();
          memberList.forEach((e) {
            _setAtMapping(
              userID: e.userID!,
              nickname: e.nickname ?? '',
              faceURL: e.faceURL,
            );
            if (!curMsgAtUser.contains(e.userID)) {
              curMsgAtUser.add(e.userID!);
              buffer.write(' @${e.userID} ');
            }
          });
          // for (var uid in uidList) {
          //   if (curMsgAtUser.contains(uid)) continue;
          //   curMsgAtUser.add(uid);
          //   buffer.write(' @$uid ');
          // }
          if (cursor < 0) cursor = 0;
          // ?????????????????????
          var start = inputCtrl.text.substring(0, cursor);
          // ?????????????????????
          var end = inputCtrl.text.substring(cursor + 1);
          inputCtrl.text = '$start$buffer$end';
          inputCtrl.selection = TextSelection.fromPosition(TextPosition(
            offset: '$start$buffer'.length,
          ));
          _lastCursorIndex = inputCtrl.selection.start;
        } else {}
      });
      return "@";
    }
    return null;
  }

  void emojiManage() {
    AppNavigator.startEmojiManage();
  }

  void addEmoji(Message message) {
    if (message.contentType == MessageType.picture) {
      var url = message.pictureElem?.sourcePicture?.url;
      var width = message.pictureElem?.sourcePicture?.width;
      var height = message.pictureElem?.sourcePicture?.height;
      cacheLogic.addFavoriteFromUrl(url, width, height);
      IMWidget.showToast(StrRes.addSuccessfully);
    } else if (message.contentType == MessageType.custom_face) {
      var index = message.faceElem?.index;
      var data = message.faceElem?.data;
      if (-1 != index) {
      } else if (null != data) {
        var map = json.decode(data);
        var url = map['url'];
        var width = map['width'];
        var height = map['height'];
        cacheLogic.addFavoriteFromUrl(url, width, height);
        IMWidget.showToast(StrRes.addSuccessfully);
      }
    }
  }

  /// ??????????????????
  void sendCustomEmoji(int index, String url) async {
    var emoji = cacheLogic.favoriteList.elementAt(index);
    var message = await OpenIM.iMManager.messageManager.createFaceMessage(
      data: json.encode({
        'url': emoji.url,
        'width': emoji.width,
        'height': emoji.height,
      }),
    );
    _sendMessage(message);
  }

  void _initChatConfig() async {
    scaleFactor.value = DataPersistence.getChatFontSizeFactor();
    var path = DataPersistence.getChatBackground() ?? '';
    if (path.isNotEmpty && (await File(path).exists())) {
      background.value = path;
    }
  }

  /// ??????????????????
  changeFontSize(double factor) async {
    await DataPersistence.putChatFontSizeFactor(factor);
    scaleFactor.value = factor;
    IMWidget.showToast(StrRes.setSuccessfully);
  }

  /// ??????????????????
  changeBackground(String path) async {
    await DataPersistence.putChatBackground(path);
    background.value = path;
    IMWidget.showToast(StrRes.setSuccessfully);
  }

  /// ??????????????????
  clearBackground() async {
    await DataPersistence.clearChatBackground();
    background.value = '';
    IMWidget.showToast(StrRes.setSuccessfully);
  }

  /// ?????????????????????
  void viewGroupMessageReadStatus(Message message) {
    AppNavigator.startGroupHaveReadList(
      message: message,
    );
  }

  /// ????????????
  void failedResend(Message message) {
    _sendMessage(message, addToUI: false);
  }

  /// ??????????????????????????????????????????
  // int getNeedReadCount(Message message) {
  //   if (isSingleChat) return 0;
  //   return groupMessageReadMembers[message.clientMsgID!]?.length ??
  //       _calNeedReadCount(message);
  // }

  /// 1???????????????
  /// 2???????????????????????????????????????????????????
  // int _calNeedReadCount(Message message) {
  //   memberList.values.forEach((element) {
  //     if (element.userID != OpenIM.iMManager.uid) {
  //       if ((element.joinTime! * 1000) < message.sendTime!) {
  //         var list = groupMessageReadMembers[message.clientMsgID!] ?? [];
  //         if (!list.contains(element.userID)) {
  //           groupMessageReadMembers[message.clientMsgID!] = list
  //             ..add(element.userID!);
  //         }
  //       }
  //     }
  //   });
  //   return groupMessageReadMembers[message.clientMsgID!]?.length ?? 0;
  // }

  /// ???????????????????????????
  bool isPrivateChat(Message message) {
    return message.attachedInfoElem?.isPrivateChat ?? false;
  }

  int readTime(Message message) {
    var isPrivate = message.attachedInfoElem?.isPrivateChat ?? false;
    var burnDuration = message.attachedInfoElem?.burnDuration ?? 30;
    if (isPrivate) {
      privateMessageList.addIf(() => !privateMessageList.contains(message), message);
      // var hasReadTime = message.attachedInfoElem!.hasReadTime ?? 0;
      var hasReadTime = message.hasReadTime ?? 0;
      if (hasReadTime > 0) {
        var end = hasReadTime + (burnDuration * 1000);

        var diff = (end - _timestamp) ~/ 1000;
        return diff < 0 ? 0 : diff;
      }
    }
    return 0;
  }

  static int get _timestamp => DateTime.now().millisecondsSinceEpoch;

  /// ????????????????????????????????????????????????????????????
  void destroyMsg() {
    privateMessageList.forEach((message) {
      OpenIM.iMManager.messageManager.deleteMessageFromLocalAndSvr(
        message: message,
      );
    });
  }

  /// ?????????????????????
  void queryMyGroupMemberInfo() async {
    if (isGroupChat) {
      var list = await OpenIM.iMManager.groupManager.getGroupMembersInfo(
        groupId: gid!,
        uidList: [OpenIM.iMManager.uid],
      );
      groupMembersInfo = list.firstOrNull;
      groupMemberRoleLevel.value = groupMembersInfo?.roleLevel ?? GroupRoleLevel.member;
      muteEndTime.value = groupMembersInfo?.muteEndTime ?? 0;
      if (null != groupMembersInfo) {
        memberUpdateInfoMap[OpenIM.iMManager.uid] = groupMembersInfo!;
      }
      _mutedClearAllInput();
    }
  }

  /// ???????????????
  void queryGroupInfo() async {
    if (isGroupChat) {
      var list = await OpenIM.iMManager.groupManager.getGroupsInfo(
        gidList: [gid!],
      );
      groupInfo = list.firstOrNull;
      if (_isExitUnreadAnnouncement()) {
        announcement.value = groupInfo?.notification ?? '';
      }
      groupMutedStatus.value = groupInfo?.status ?? 0;
      memberCount.value = groupInfo?.memberCount ?? 0;
      isValidChat.value = groupInfo?.status == 0;
      queryMyGroupMemberInfo();
      queryGroupCallingInfo();
    }
  }

  /// ????????????
  /// 1????????????, 2?????????3?????????
  bool get havePermissionMute =>
      isGroupChat &&
      (groupInfo?.ownerUserID ==
          OpenIM.iMManager.uid /*||
          groupMembersInfo?.roleLevel == 2*/
      );

  /// ??????????????????
  bool isNotificationType(Message message) => message.contentType! >= 1000;

  Map<String, String> getAtMapping(Message message) {
    if (isGroupChat) {
      if (message.contentType == MessageType.at_text) {
        var list = message.atElem!.atUsersInfo;
        list?.forEach((e) {
          atUserNameMappingMap[e.atUserID!] = IMUtil.getAtNickname(e.atUserID!, e.groupNickname!);
        });
      }
      return atUserNameMappingMap;
    }
    return {};
  }

  void queryUserOnlineStatus() {
    if (isSingleChat) {
      Apis.queryUserOnlineStatus(
        uidList: [uid!],
        onlineStatusCallback: (map) {
          onlineStatus.value = map[uid]!;
        },
        onlineStatusDescCallback: (map) {
          onlineStatusDesc.value = map[uid]!;
        },
      );
    }
  }

  /// ????????????????????????
  void lockMessageLocation(Message message) {
    // var upList = list.sublist(0, 15);
    // var downList = list.sublist(15);
    // messageList.assignAll(downList);
    // WidgetsBinding.instance?.addPostFrameCallback((timeStamp) {
    //   scrollController.jumpTo(scrollController.position.maxScrollExtent - 50);
    //   messageList.insertAll(0, upList);
    // });
  }

  void _checkInBlacklist() async {
    if (uid != null) {
      var list = await OpenIM.iMManager.friendshipManager.getBlacklist();
      var user = list.firstWhereOrNull((e) => e.userID == uid);
      isInBlacklist.value = user != null;
    }
  }

  void _setAtMapping({
    required String userID,
    required String nickname,
    String? faceURL,
  }) {
    atUserNameMappingMap[userID] = nickname;
    atUserInfoMappingMap[userID] = UserInfo(
      userID: userID,
      nickname: nickname,
      faceURL: faceURL,
    );
    DataPersistence.putAtUserMap(gid!, atUserNameMappingMap);
  }

  /// ?????????24??????
  bool isExceed24H(Message message) {
    int milliseconds = message.sendTime!;
    return !DateUtil.isToday(milliseconds);
  }

  bool isPlaySound(Message message) {
    return _currentPlayClientMsgID.value == message.clientMsgID!;
  }

  void _initPlayListener() {
    _audioPlayer.playerStateStream.listen((state) {
      switch (state.processingState) {
        case ProcessingState.idle:
        case ProcessingState.loading:
        case ProcessingState.buffering:
        case ProcessingState.ready:
          break;
        case ProcessingState.completed:
          _currentPlayClientMsgID.value = "";
          break;
      }
    });
  }

  /// ??????????????????
  void _playVoiceMessage(Message message) async {
    var isClickSame = _currentPlayClientMsgID.value == message.clientMsgID;
    if (_audioPlayer.playerState.playing) {
      _currentPlayClientMsgID.value = "";
      _audioPlayer.stop();
    }
    if (!isClickSame) {
      bool isValid = await _initVoiceSource(message);
      if (isValid) {
        _audioPlayer.seek(Duration.zero);
        _audioPlayer.play();
        _currentPlayClientMsgID.value = message.clientMsgID!;
      }
    }
  }

  /// ????????????????????????
  Future<bool> _initVoiceSource(Message message) async {
    bool isReceived = message.sendID != OpenIM.iMManager.uid;
    String? path = message.soundElem?.soundPath;
    String? url = message.soundElem?.sourceUrl;
    bool isExistSource = false;
    if (isReceived) {
      if (null != url && url.trim().isNotEmpty) {
        isExistSource = true;
        _audioPlayer.setUrl(url);
      }
    } else {
      var _existFile = false;
      if (path != null && path.trim().isNotEmpty) {
        var file = File(path);
        _existFile = await file.exists();
      }
      if (_existFile) {
        isExistSource = true;
        _audioPlayer.setFilePath(path!);
      } else if (null != url && url.trim().isNotEmpty) {
        isExistSource = true;
        _audioPlayer.setUrl(url);
      }
    }
    return isExistSource;
  }

  /// ??????????????????????????????
  void onPopMenuShowChanged(show) {
    isShowPopMenu.value = show;
    if (!show && _showMenuCacheMessageList.isNotEmpty) {
      messageList.addAll(_showMenuCacheMessageList);
      _showMenuCacheMessageList.clear();
    }
  }

  String? newestNickname(Message message) {
    if (isSingleChat) return null;
    return memberUpdateInfoMap[message.sendID]?.nickname;
  }

  /// ?????????????????????
  bool _isExitUnreadAnnouncement() =>
      conversationInfo?.groupAtType == GroupAtType.groupNotification;

  /// ???????????????
  bool isAnnouncementMessage(message) => _getAnnouncement(message) != null;

  String? _getAnnouncement(Message message) {
    if (message.contentType! == MessageType.groupInfoSetNotification) {
      final elem = message.notificationElem!;
      final map = json.decode(elem.detail!);
      final notification = GroupNotification.fromJson(map);
      if (notification.group?.notification != null &&
          notification.group!.notification!.isNotEmpty) {
        return notification.group!.notification!;
      }
    }
    return null;
  }

  /// ??????????????????
  void _parseAnnouncement(Message message) {
    var ac = _getAnnouncement(message);
    if (null != ac) {
      announcement.value = ac;
      groupInfo?.notification = ac;
    }
  }

  /// ????????????
  void previewGroupAnnouncement() async {
    if (null != groupInfo) {
      announcement.value = '';
      await AppNavigator.startEditAnnouncement(groupID: groupInfo!.groupID);
    }
  }

  /// ????????????????????????????????????????????????????????????
  bool get isMuted => isGroupMuted || isUserMuted || isInBlacklist.value;

  /// ??????????????????????????????????????????
  bool get isGroupMuted =>
      groupMutedStatus.value == 3 && groupMemberRoleLevel.value == GroupRoleLevel.member;

  /// ???????????????
  bool get isUserMuted => muteEndTime.value * 1000 > DateTime.now().millisecondsSinceEpoch;

  /// ????????? ??????????????????
  void _mutedClearAllInput() {
    if (isMuted) {
      inputCtrl.clear();
      setQuoteMsg(null);
      closeMultiSelMode();
    }
  }

  /// ?????????????????????
  void _resetGroupAtType() {
    // ????????????@??????/????????????
    if (null != conversationInfo && conversationInfo!.groupAtType != GroupAtType.atNormal) {
      OpenIM.iMManager.conversationManager.resetConversationGroupAtType(
        conversationID: conversationInfo!.conversationID,
      );
    }
  }

  String getTitle() => memberCount.value > 0 ? '${name.value}(${memberCount.value})' : name.value;

  /// ???????????????????????????
  void revokeMsgV2(Message message) async {
    late bool canRevoke;
    if (isGroupChat) {
      // ?????????????????????
      if (message.sendID == OpenIM.iMManager.uid) {
        canRevoke = true;
      } else {
        // ??????????????????????????????????????????
        var list = await LoadingView.singleton.wrap(
            asyncFunction: () => OpenIM.iMManager.groupManager.getGroupOwnerAndAdmin(
                  groupID: gid!,
                ));
        var sender = list.firstWhereOrNull((e) => e.userID == message.sendID);
        var revoker = list.firstWhereOrNull((e) => e.userID == OpenIM.iMManager.uid);

        if (revoker != null && sender == null) {
          // ?????????????????????????????? ????????????
          canRevoke = true;
        } else if (revoker == null && sender != null) {
          // ???????????????????????????????????????????????????????????? ????????????
          canRevoke = false;
        } else if (revoker != null && sender != null) {
          if (revoker.roleLevel == sender.roleLevel) {
            // ????????? ????????????
            canRevoke = false;
          } else if (revoker.roleLevel == GroupRoleLevel.owner) {
            // ??????????????????  ?????????
            canRevoke = true;
          } else {
            // ????????????
            canRevoke = false;
          }
        } else {
          // ???????????? ????????????
          canRevoke = false;
        }
      }
    } else {
      // ?????????????????????
      if (message.sendID == OpenIM.iMManager.uid) {
        canRevoke = true;
      }
    }
    if (canRevoke) {
      await OpenIM.iMManager.messageManager.revokeMessageV2(message: message);
      message.contentType = MessageType.advancedRevoke;
      message.content = jsonEncode(_buildRevokeInfo(message));
      messageList.refresh();
    } else {
      IMWidget.showToast('??????????????????????????????!');
    }
  }

  RevokedInfo _buildRevokeInfo(Message message) {
    return RevokedInfo.fromJson({
      'revokerID': OpenIM.iMManager.uInfo.userID,
      'revokerRole': 0,
      'revokerNickname': OpenIM.iMManager.uInfo.nickname,
      'clientMsgID': message.clientMsgID,
      'revokeTime': 0,
      'sourceMessageSendTime': 0,
      'sourceMessageSendID': message.sendID,
      'sourceMessageSenderNickname': message.senderNickname,
      'sessionType': message.sessionType,
    });
  }

  /// ????????????
  bool showCopyMenu(Message message) {
    return message.contentType == MessageType.text;
  }

  /// ????????????
  bool showDelMenu(Message message) {
    if (isPrivateChat(message)) {
      return false;
    }
    return true;
  }

  /// ????????????
  bool showForwardMenu(Message message) {
    if (isNoticeMessage(message) ||
        isPrivateChat(message) ||
        isCallMessage(message) ||
        message.contentType == MessageType.voice) {
      return false;
    }
    return true;
  }

  /// ????????????
  bool showReplyMenu(Message message) {
    // if (isNoticeMessage(message) ||
    //     isPrivateChat(message) ||
    //     isCallMessage(message)) {
    //   return false;
    // }
    return message.contentType == MessageType.text ||
        message.contentType == MessageType.video ||
        message.contentType == MessageType.picture ||
        message.contentType == MessageType.location ||
        message.contentType == MessageType.quote;
  }

  /// ??????????????????????????????
  bool showRevokeMenu(Message message) {
    if (isNoticeMessage(message) ||
        isCallMessage(message) ||
        isExceed24H(message) && isSingleChat) {
      return false;
    }
    if (isGroupChat) {
      return true;
    }
    return message.sendID == OpenIM.iMManager.uid;
  }

  /// ????????????
  bool showMultiMenu(Message message) {
    if (isNoticeMessage(message) || isPrivateChat(message) || isCallMessage(message)) {
      return false;
    }
    return true;
  }

  /// ??????????????????
  bool showAddEmojiMenu(Message message) {
    if (isPrivateChat(message)) {
      return false;
    }
    return message.contentType == MessageType.picture ||
        message.contentType == MessageType.custom_face;
  }

  /// ??????????????????????????????????????????
  bool isNoticeMessage(Message message) => message.contentType! > 1000;

  bool showCheckbox(Message message) {
    if (isNoticeMessage(message) || isPrivateChat(message) || isCallMessage(message)) {
      return false;
    }
    return multiSelMode.value;
  }

  WillPopCallback? willPop() {
    return multiSelMode.value || isShowPopMenu.value ? () async => exit() : null;
  }

  void expandCallingMemberPanel() {
    showCallingMember.value = !showCallingMember.value;
  }

  void queryGroupCallingInfo() async {
    roomCallingInfo = await OpenIM.iMManager.signalingManager.signalingGetRoomByGroupID(
      groupID: groupInfo!.groupID,
    );
    if (roomCallingInfo.participant != null && roomCallingInfo.participant!.isNotEmpty) {
      participants.assignAll(roomCallingInfo.participant!);
    }
  }

  /// ??????????????????????????????????????????????????????????????????
  void onScrollToTop() {
    if (_scrollingCacheMessageList.isNotEmpty) {
      messageList.addAll(_scrollingCacheMessageList);
      _scrollingCacheMessageList.clear();
    }
  }

  String get markText {
    String? phoneNumber = OpenIM.iMManager.uInfo.phoneNumber;
    if (phoneNumber != null) {
      int start = phoneNumber.length > 4 ? phoneNumber.length - 4 : 0;
      final sub = phoneNumber.substring(start);
      return "${OpenIM.iMManager.uInfo.nickname!}$sub";
    }
    return OpenIM.iMManager.uInfo.nickname!;
  }

  bool isFailedHintMessage(Message message) {
    if (message.contentType == MessageType.custom) {
      var data = message.customElem!.data;
      var map = json.decode(data!);
      var customType = map['customType'];
      return customType == CustomMessageType.deletedByFriend ||
          customType == CustomMessageType.blockedByFriend;
    }
    return false;
  }

  void sendFriendVerification() {
    AppNavigator.startSendFriendRequest(info: UserInfo(userID: uid));
  }
}
