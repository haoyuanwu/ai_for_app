/// Phone records store the contact's supplied name in title.
class PhoneRecord {
  static bool hasName(dynamic value) {
    if (value is! String) return false;
    final name = value.trim();
    if (name.isEmpty || !RegExp(r'[A-Za-z\u3400-\u9fff]').hasMatch(name)) {
      return false;
    }
    if (RegExp(
      r'^(?:电话|电话号码|号码|联系人|联系电话|手机号|手机号码|电话记录|未知|未命名|未提供|待补充|姓名待补充|联系人待补充|某人|朋友|同事|客户|用户|我的电话|我的号码|记录电话|保存电话)$',
    ).hasMatch(name)) {
      return false;
    }
    return true;
  }

  static bool hasNumber(dynamic value) =>
      value is String &&
      RegExp(r'^\+?[0-9 ()-]{5,25}$').hasMatch(value.trim()) &&
      value.replaceAll(RegExp(r'\D'), '').length >= 5;
}
