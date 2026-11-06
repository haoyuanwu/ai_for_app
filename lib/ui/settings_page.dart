import 'package:flutter/material.dart';

import '../core/assistant_persona.dart';
import '../core/local_store.dart';
import '../core/speech_preferences.dart';

import 'package:flutter/foundation.dart';

import 'assistant_persona_page.dart';
import 'models_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store});
  final LocalStore store;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool saving = false;
  String? error;

  Future<void> setModel(ModelRole role, String id) async {
    final previous = widget.store.selected[role.name];
    setState(() {
      saving = true;
      error = null;
    });
    if (id == 'auto') {
      widget.store.selected.remove(role.name);
    } else {
      widget.store.selected[role.name] = id;
    }
    try {
      await widget.store.save();
    } catch (_) {
      if (previous == null) {
        widget.store.selected.remove(role.name);
      } else {
        widget.store.selected[role.name] = previous;
      }
      if (mounted) setState(() => error = '设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget modelPicker(ModelRole role, String label) {
    final candidates = widget.store.models.entries
        .where(
          (entry) =>
              LocalStore.capabilities(entry.value as Map<String, dynamic>)
                  .contains(role.name),
        )
        .toList();
    final selected = widget.store.selected[role.name];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: DropdownButtonFormField<String>(
        key: ValueKey('function-model-${role.name}-$selected'),
        initialValue: candidates.any((entry) => entry.key == selected)
            ? selected as String
            : 'auto',
        decoration: InputDecoration(labelText: label),
        isExpanded: true,
        items: [
          const DropdownMenuItem(
            value: 'auto',
            child: Text(
              '自动选择本地模型',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          for (final entry in candidates)
            DropdownMenuItem(
              value: entry.key,
              child: Text(
                entry.value['name'] as String,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: saving
            ? null
            : (id) {
                if (id != null) setModel(role, id);
              },
      ),
    );
  }

  Future<void> setTranscriber(String value) async {
    final previous = widget.store.data['speechTranscriber'];
    final previousModel = widget.store.selected['speech'];
    setState(() {
      saving = true;
      error = null;
    });
    widget.store.data['speechTranscriber'] = value == 'native'
        ? 'native'
        : 'model';
    if (value == 'auto') {
      widget.store.selected.remove('speech');
    }
    if (value.startsWith('model:')) {
      widget.store.selected['speech'] = value.substring(6);
    }
    try {
      await widget.store.save();
    } catch (_) {
      if (previous == null) {
        widget.store.data.remove('speechTranscriber');
      } else {
        widget.store.data['speechTranscriber'] = previous;
      }
      if (previousModel == null) {
        widget.store.selected.remove('speech');
      } else {
        widget.store.selected['speech'] = previousModel;
      }
      if (mounted) setState(() => error = '设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> setLiveSpeech(bool enabled) async {
    final previous = widget.store.data['liveSpeechEnabled'];
    setState(() {
      saving = true;
      error = null;
    });
    widget.store.data['liveSpeechEnabled'] = enabled;
    try {
      await widget.store.save();
    } catch (_) {
      if (previous == null) {
        widget.store.data.remove('liveSpeechEnabled');
      } else {
        widget.store.data['liveSpeechEnabled'] = previous;
      }
      if (mounted) setState(() => error = '设置保存失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> open(Widget page) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => page),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('设置')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text('模型'),
                      subtitle: const Text('管理文字、图片和语音模型'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => open(ModelsPage(store: widget.store)),
                    ),
                    const Divider(height: 1, indent: 52),
                    ListTile(
                      leading: const Icon(Icons.face_outlined),
                      title: const Text('AI 人设'),
                      subtitle: Text(
                        AssistantPersona.read(widget.store.data)['name']!,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () =>
                          open(AssistantPersonaPage(store: widget.store)),
                    ),
                    const Divider(height: 1, indent: 52),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '功能使用的模型',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    modelPicker(ModelRole.chat, '文字对话'),
                    modelPicker(ModelRole.vision, '图片识别'),
                    modelPicker(ModelRole.speech, '语音气泡转文字模型'),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'speech-transcriber-${widget.store.data['speechTranscriber']}-${widget.store.selected['speech']}',
                        ),
                        initialValue:
                            SpeechPreferences.useNative(widget.store.data)
                            ? 'native'
                            : widget.store.selected['speech'] is String &&
                                  widget.store.models[widget
                                          .store
                                          .selected['speech']] !=
                                      null
                            ? 'model:${widget.store.selected['speech']}'
                            : 'auto',
                        decoration: const InputDecoration(labelText: '语音录入转写'),
                        isExpanded: true,
                        items: [
                          if (defaultTargetPlatform == TargetPlatform.iOS)
                            const DropdownMenuItem(
                              value: 'native',
                              child: Text(
                                '系统原生实时转写（默认）',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          const DropdownMenuItem(
                            value: 'auto',
                            child: Text(
                              '本地模型（自动选择）',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final entry in widget.store.models.entries)
                            if (LocalStore.capabilities(
                              entry.value as Map<String, dynamic>,
                            ).contains('speech'))
                              DropdownMenuItem(
                                value: 'model:${entry.key}',
                                child: Text(
                                  entry.value['name'] as String,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                        ],
                        onChanged: saving
                            ? null
                            : (value) {
                                if (value != null) setTranscriber(value);
                              },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Text(
                        SpeechPreferences.useNative(widget.store.data)
                            ? '录入使用 iOS 系统离线识别；语音气泡的“转文字”使用上方本地模型。'
                            : '使用手机内的语音模型，不依赖 Google 语音服务。',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (!SpeechPreferences.useNative(widget.store.data))
                      SwitchListTile(
                        secondary: const Icon(Icons.mic_none),
                        title: const Text('边说边识别'),
                        subtitle: const Text('录音时显示转写文字，不支持时自动在松手后转文字。'),
                        value: widget.store.data['liveSpeechEnabled'] == true,
                        onChanged: saving ? null : setLiveSpeech,
                      ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
