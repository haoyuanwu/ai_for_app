import 'package:flutter/material.dart';

import '../core/assistant_persona.dart';
import '../core/local_store.dart';

class AssistantPersonaPage extends StatefulWidget {
  const AssistantPersonaPage({super.key, required this.store});
  final LocalStore store;

  @override
  State<AssistantPersonaPage> createState() => _AssistantPersonaPageState();
}

class _AssistantPersonaPageState extends State<AssistantPersonaPage> {
  static const labels = {
    'name': '姓名',
    'personality': '性格',
    'interests': '兴趣',
    'style': '对话风格',
  };
  final form = GlobalKey<FormState>();
  late final fields = {
    for (final entry in AssistantPersona.read(widget.store.data).entries)
      entry.key: TextEditingController(text: entry.value),
  };
  bool saving = false;
  String? error;

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (saving || !form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      saving = true;
      error = null;
    });
    final previous = widget.store.data['assistantPersona'];
    widget.store.data['assistantPersona'] = {
      for (final entry in fields.entries) entry.key: entry.value.text.trim(),
    };
    try {
      await widget.store.save();
    } catch (_) {
      if (previous == null) {
        widget.store.data.remove('assistantPersona');
      } else {
        widget.store.data['assistantPersona'] = previous;
      }
      if (mounted) {
        setState(() {
          saving = false;
          error = '保存失败，请重试';
        });
      }
      return;
    }
    if (mounted) {
      setState(() => saving = false);
      // Let PopScope observe the completed save before closing the form.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('AI 人设')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Text('基本信息', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    '设置 AI 的名字和交流方式，也可以在对话中修改。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  for (final entry in labels.entries) ...[
                    TextFormField(
                      key: ValueKey('persona_${entry.key}'),
                      controller: fields[entry.key],
                      enabled: !saving,
                      decoration: InputDecoration(
                        labelText: entry.value,
                        alignLabelWithHint: true,
                      ),
                      minLines: 1,
                      maxLines: entry.key == 'name' ? 1 : 4,
                      maxLength: entry.key == 'name' ? 40 : 500,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? '请输入${entry.value}'
                          : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
