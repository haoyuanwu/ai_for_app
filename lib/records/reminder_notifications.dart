import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

abstract class ReminderScheduler {
  Future<String> schedule(
    int id,
    String title,
    DateTime at, {
    bool requestPermission = true,
  });
  Future<void> cancel(int id);
}

class ReminderNotifications implements ReminderScheduler {
  final plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  Future<void> initialize() => _ready ??= _initialize().catchError((Object e) {
    _ready = null;
    throw e;
  });
  Future<void> _initialize() async {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(
      tz.getLocation((await FlutterTimezone.getLocalTimezone()).identifier),
    );
    await plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_reminder'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  @override
  Future<String> schedule(
    int id,
    String title,
    DateTime at, {
    bool requestPermission = true,
  }) async {
    if (!at.isAfter(DateTime.now())) throw StateError('提醒时间已过去，请重新选择');
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('本地提醒目前支持 Android 和 iOS');
    }
    await initialize();
    var mode = AndroidScheduleMode.inexactAllowWhileIdle;
    if (Platform.isAndroid) {
      final android = plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()!;
      final allowed = requestPermission
          ? await android.requestNotificationsPermission()
          : await android.areNotificationsEnabled();
      if (allowed != true) throw StateError('通知权限未开启，请在系统设置开启后重试');
      // Do not silently launch a special-permission settings page. Fall back visibly.
      if (await android.canScheduleExactNotifications() == true) {
        mode = AndroidScheduleMode.exactAllowWhileIdle;
      }
    } else {
      final ios = plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()!;
      final allowed = requestPermission
          ? await ios.requestPermissions(alert: true, badge: true, sound: true)
          : (await ios.checkPermissions())?.isEnabled;
      if (allowed != true) throw StateError('通知权限未开启，请在系统设置开启后重试');
      final pending = await plugin.pendingNotificationRequests();
      if (pending.where((p) => p.id != id).length >= 60) {
        throw StateError('待提醒数量已达上限，请先取消部分提醒');
      }
    }
    await plugin.zonedSchedule(
      id: id,
      title: '本地随记 · 提醒',
      body: title,
      scheduledDate: tz.TZDateTime.from(at, tz.local),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'personal_reminders',
          '个人提醒',
          channelDescription: '通过对话创建的单次提醒',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
      androidScheduleMode: mode,
      payload: 'record:$id',
    );
    return Platform.isAndroid &&
            mode == AndroidScheduleMode.inexactAllowWhileIdle
        ? 'scheduled_inexact'
        : 'scheduled';
  }

  Future<bool> requestExactPermission() async {
    if (!Platform.isAndroid) return false;
    await initialize();
    return await plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()!
            .requestExactAlarmsPermission() ==
        true;
  }

  @override
  Future<void> cancel(int id) async {
    await initialize();
    await plugin.cancel(id: id);
  }
}
