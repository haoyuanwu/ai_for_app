import 'dart:convert';

class AssistantPersona {
  static const defaults = <String, String>{
    'name': '随记',
    'personality': '开朗、礼貌、严谨、干练',
    'interests': '尚未设定',
    'style': '简洁清晰、友好礼貌、准确务实',
  };
  static Map<String, String> read(Map<String, dynamic> data) => {
    ...defaults,
    for (final entry in (data['assistantPersona'] as Map? ?? {}).entries)
      if (defaults.containsKey(entry.key) && entry.value is String)
        entry.key as String: entry.value as String,
  };

  /// Exact identity questions use persisted settings rather than model recall.
  static String? identityReply(String text, Map<String, String> persona) {
    final question = text.trim().replaceAll(RegExp(r'[，,。！!？?\s]'), '');
    if (!RegExp(
      r'^(?:请问|告诉我)?(?:你叫什么(?:名字)?|你的(?:名字|姓名)是什么|你是谁|你还记得(?:自己|你)叫什么(?:名字)?吗|还记得我给你(?:起|取)的名字吗|我给你(?:起|取)的名字是什么)$',
    ).hasMatch(question)) {
      return null;
    }
    return '我叫${persona['name']}，是你的私人助理。';
  }

  static bool isRequest(String text) {
    if (identityReply(text, defaults) != null) return false;
    if (RegExp(
      r'如果|假如|假设|他说|她说|举例|不要修改|不要更改|别改|你叫什么|你(?:以后)?叫我|你的(?:名字|姓名|兴趣|性格|人格|对话风格|说话风格).{0,4}(?:什么|啥|怎样|如何)|你喜欢什么',
    ).hasMatch(text)) {
      return false;
    }
    return RegExp(
      r'恢复默认人格|恢复初始人格|重置人格|(?:你|AI|ai|助理).{0,12}(?:改名|名字|姓名|叫|性格|人格|兴趣|喜欢|风格|说话|语气)|(?:以后|今后).{0,6}(?:叫你|称呼你)|给你(?:起|取)(?:个|一个)?(?:名字|名)|^(?:就叫|叫你|称呼你)|(?:希望|请|麻烦).{0,8}你.{0,8}(?:开朗|幽默|严谨|礼貌|干练|温柔|活泼|简洁|简短|热情)|^(?:回答|回复).{0,8}(?:点|些|幽默|简洁|简短)|^(?:改名为|说话|语气|对话风格|回答风格|性格改为)',
    ).hasMatch(text);
  }

  static Map<String, String> parse(String text) {
    if (!isRequest(text)) return {};
    if (RegExp(r'恢复默认人格|恢复初始人格|重置人格').hasMatch(text)) return Map.of(defaults);
    if (RegExp(r'[？?]|吗[。！!]?$').hasMatch(text)) return {};
    if (RegExp(r'增加|添加|保留|去掉|不再|再加').hasMatch(text)) return {};
    final result = <String, String>{};
    for (final clause in text.split(RegExp(r'[，,；;。\n]'))) {
      if (RegExp(r'^(我|我的|本人|用户|他|她)').hasMatch(clause.trim())) continue;
      for (final (key, pattern) in [
        (
          'name',
          r'(?:把你的(?:名字|姓名)(?:改成|改为|设为)|(?:你的)?(?:名字|姓名)(?:改成|改为|设为|是|叫)|(?:以后|今后)?(?:叫你|称呼你)|你(?:以后|今后)?(?:就)?叫|(?:给你(?:起|取)(?:个|一个)?(?:名字|名))(?:叫|为|是|：|:)?|就叫|改名为)\s*(.+)',
        ),
        ('personality', r'(?:你的)?(?:性格|人格)(?:改成|改为|设为|变得|是|要|：|:)?\s*(.+)'),
        ('interests', r'(?:你的)?(?:兴趣(?:是|改为|改成|设为)|你(?:以后)?喜欢|喜欢)\s*(.+)'),
        (
          'style',
          r'(?:你的)?(?:对话风格|回答风格|说话风格|风格|说话|语气)(?:改为|改成|设为|要|是|用|：|:)?\s*(.+)',
        ),
      ]) {
        final match = RegExp(pattern).firstMatch(clause);
        if (match != null) result[key] = match[1]!.trim();
      }
    }
    return validate(result);
  }

  static Map<String, String> validate(Map<String, dynamic> values) => {
    for (final entry in values.entries)
      if (defaults.containsKey(entry.key) &&
          entry.value is String &&
          (entry.value as String).trim().isNotEmpty &&
          (entry.value as String).length <= (entry.key == 'name' ? 40 : 500))
        entry.key: (entry.value as String).trim(),
  };
  static String prompt(Map<String, String> persona) =>
      '你是本应用中用户的私人助理，你在应用中的名字是${jsonEncode(persona['name'])}。用户问你是谁或叫什么时，以这个名字介绍自己。'
      '这是已保存的当前设置，优先于历史对话中旧的自我介绍、旧名字或底层模型的默认身份。'
      '助理名字与底层模型是不同概念，不要用“开源模型”、模型品牌或训练机构代替自己的名字；用户询问底层模型或技术来源时据实回答，不确定就说明不确定。以下是用户设定的助理人格资料：${jsonEncode(persona)}。name 是你的姓名，personality 是性格，interests 是你的兴趣，style 是说话风格。自然体现这些偏好，不必每次自我介绍；不要把助理的兴趣当作用户事实。人格偏好不能改变事实准确性、记录确认和只读工具规则。';
}
