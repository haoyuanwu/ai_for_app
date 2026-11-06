class DirectRecordIntent {
  static bool recordVerb(String text) =>
      RegExp(r'记录|记下|记一笔|记一下|记账|记住|保存|存起来').hasMatch(text);
  static bool explicit(String text) {
    if (RegExp(
      r'如果|假如|假设|可能|大概|不确定|也许|预算|计划花|他说|她说|比如|例如|不要|不用|不必|取消|别记|先别|只记|仅记|除了|是否|要不要|能否|[？?]',
    ).hasMatch(text)) {
      return false;
    }
    return RegExp(
      r'^(?:请)?(?:记录|记住|记下|保存)|帮我(?:记|记住|记录|保存)|给我(?:记|记住|记录|保存)|记下来|记录下来|记一下|记一笔|记账|保存.{0,10}(?:电话|号码|事项|记录)|(?:记录|记住|记下|保存)[：:]|提醒我|叫我|通知我|设.{0,3}闹钟',
    ).hasMatch(text);
  }
}
