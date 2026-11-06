import 'local_store.dart';
import '../records/direct_record_intent.dart';

/// Route by actual input, reusing a picture only when the user refers to it.
class ConversationRoute {
  const ConversationRoute(this.image);
  final String? image;
  ModelRole get role => image == null ? ModelRole.chat : ModelRole.vision;

  static ConversationRoute resolve(
    String text, {
    String? attachedImage,
    required List<dynamic> history,
  }) {
    if (attachedImage != null) return ConversationRoute(attachedImage);
    final refersToImage = RegExp(
      r'(?:这|那|刚才|刚刚|上面|之前|前面|上一张).{0,8}(?:图|照|收据)|(?:图片|图|照片)[中里上]|上一张',
    ).hasMatch(text);
    final lastUser = history.reversed
        .where((message) => message['role'] == 'user')
        .firstOrNull;
    final lastImageContext = lastUser?['image'] ?? lastUser?['contextImage'];
    final recordImageFacts =
        lastImageContext is String &&
        lastUser?['status'] == 'done' &&
        DirectRecordIntent.recordVerb(text) &&
        RegExp(
          r'(?:这|那).{0,8}(?:人|条|笔|项|信息|内容)|他们|她们|上面|刚才|刚刚|^(?:请)?(?:帮我)?(?:记录|保存|记下)(?:一下|下来|吧)?[。！!]*$',
        ).hasMatch(text);
    final immediateFollowup =
        lastImageContext is String &&
        lastUser?['status'] == 'done' &&
        RegExp(
          r'^(?:继续|还有呢|再看看|详细一点|说详细点|多少钱|一共多少钱|什么颜色|有几个人|写了什么|能看清吗)[？?！!。]*$',
        ).hasMatch(text.trim());
    if (refersToImage || immediateFollowup || recordImageFacts) {
      for (final message in history.reversed) {
        if (message['role'] == 'user' &&
            message['status'] == 'done' &&
            message['image'] is String) {
          return ConversationRoute(message['image'] as String);
        }
      }
    }
    return const ConversationRoute(null);
  }
}
