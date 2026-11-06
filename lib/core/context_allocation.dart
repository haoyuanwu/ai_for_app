/// Retry only native context allocation failures, never corrupt models, missing
/// assets or inference/validation errors. Keep context capacity unchanged.
class ContextAllocation {
  static bool canRetry(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('could not create context') ||
        text.contains('failed to create context') ||
        text.contains('failed to allocate') ||
        text.contains('out of memory');
  }

  static Future<T> load<T>({
    required bool useGpu,
    required Future<T> Function(bool gpu) create,
  }) async {
    try {
      return await create(useGpu);
    } catch (error) {
      if (!useGpu || !canRetry(error)) rethrow;
      // The failed native constructor has unwound before a new allocation.
      await Future<void>.delayed(const Duration(milliseconds: 120));
      try {
        return await create(false);
      } catch (fallback) {
        throw StateError(
          '本地模型无法分配推理内存，GPU 与 CPU 均创建失败。请关闭其他应用或选择更小的模型后重试。原消息已保留。详细原因：$fallback',
        );
      }
    }
  }
}
