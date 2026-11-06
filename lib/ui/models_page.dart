import '../models/gguf_context_metadata.dart';

import 'dart:io';

import 'package:dio/dio.dart';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/local_store.dart';
import '../models/model_library.dart';
import '../models/speech_bundle.dart';
import '../models/model_package.dart';
import '../models/model_file_export.dart';
import 'model_catalog_page.dart';

class ModelsPage extends StatefulWidget {
  const ModelsPage({
    super.key,
    required this.store,
    this.initialAction,
    this.initialModelId,
    this.initialRole,
    this.importPackageInitially = false,
  });
  final String? initialAction, initialModelId, initialRole;
  final bool importPackageInitially;
  final LocalStore store;
  @override
  State<ModelsPage> createState() => _ModelsPageState();
}

class _ModelsPageState extends State<ModelsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (widget.initialAction == 'export_model' &&
          widget.initialModelId != null) {
        await exportModel(widget.initialModelId!);
      } else if (widget.initialAction == 'import_model') {
        if (widget.importPackageInitially) {
          await importPackage();
        } else {
          await importModel(
            ModelRole.values
                    .where((r) => r.name == widget.initialRole)
                    .firstOrNull ??
                ModelRole.chat,
          );
        }
      }
    });
  }

  bool busy = false;
  String? status;
  Future<void> importModel(ModelRole role, {bool download = false}) async {
    String? url;
    if (download) {
      final input = TextEditingController();
      url = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('从下载链接获取模型'),
          content: TextField(
            controller: input,
            decoration: const InputDecoration(
              labelText: 'HTTPS 文件直链',
              helperText: 'GGUF 或完整语音模型 ZIP',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, input.text.trim()),
              child: const Text('下载'),
            ),
          ],
        ),
      );
      // The route transition may still use the controller; let it be collected.
      if (url == null) return;
    }
    setState(() {
      busy = true;
      status = '准备${role.label}模型…';
    });
    Directory? directory;
    Dio? client;
    try {
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      directory = await Directory('${widget.store.root.path}/models/$id')
          .create(recursive: true);
      String source;
      String name;
      if (url != null) {
        final uri = Uri.parse(url);
        if (uri.scheme != 'https' || uri.host.isEmpty) {
          throw const FormatException('请使用 HTTPS 文件直链');
        }
        name = uri.pathSegments.last;
        if (!(name.endsWith(role == ModelRole.speech ? '.zip' : '.gguf'))) {
          throw const FormatException('文件格式不匹配');
        }
        source = '${directory.path}/download.part';
        client = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 30),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        await client.download(
          uri.toString(),
          source,
          deleteOnError: true,
          onReceiveProgress: (received, total) {
            if (mounted) {
              setState(
                () => status =
                    '已下载 ${(received / 1048576).toStringAsFixed(1)} MB${total > 0 ? ' / ${(total / 1048576).toStringAsFixed(1)} MB' : ''}',
              );
            }
          },
        );
      } else {
        final result = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: [role == ModelRole.speech ? 'zip' : 'gguf'],
        );
        if (result.isEmpty) return;
        source = result.single.path!;
        name = result.single.name;
      }
      String path;
      var format = 'gguf';
      String? projection;
      var capabilities = <String>['speech'];
      if (role != ModelRole.speech) {
        var vision = role == ModelRole.vision;
        var speech = false;
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('标记模型能力'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('请根据模型说明选择。能力标记不是兼容性检测，图片或音频输入需要配套投影。文字对话默认支持。'),
                  CheckboxListTile(
                    title: const Text('支持图片输入'),
                    value: vision,
                    onChanged: (v) => update(() => vision = v!),
                  ),
                  CheckboxListTile(
                    title: const Text('支持音频输入 / 转写'),
                    value: speech,
                    onChanged: (v) => update(() => speech = v!),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('继续导入'),
                ),
              ],
            ),
          ),
        );
        if (confirmed != true) return;
        capabilities = ['chat', if (vision) 'vision', if (speech) 'speech'];
      }
      if (role == ModelRole.speech) {
        if (mounted) setState(() => status = '解压语音模型…');
        final input = InputFileStream(source);
        try {
          final archive = ZipDecoder().decodeStream(input);
          // Reject traversal and symlinks before extraction.
          for (final entry in archive) {
            if (entry.isSymbolicLink ||
                entry.name.startsWith('/') ||
                entry.name.contains('..') ||
                entry.name.contains('\\')) {
              throw const FormatException('压缩包含不安全路径');
            }
          }
          await extractArchiveToDisk(archive, '${directory.path}/speech');
        } finally {
          await input.close();
        }
        final bundle = await SpeechBundle.detect(
          Directory('${directory.path}/speech'),
        );
        path = bundle.path;
        format = bundle.format;
      } else {
        path = '${directory.path}/model.gguf';
        await File(source).copy(path);
        final handle = await File(path).open();
        try {
          if (String.fromCharCodes(await handle.read(4)) != 'GGUF') {
            throw const FormatException('不是有效的 GGUF 文件');
          }
        } finally {
          await handle.close();
        }
        if (capabilities.contains('vision') ||
            capabilities.contains('speech')) {
          if (mounted) setState(() => status = '请选择与图片模型配套的 mmproj GGUF');
          final result = await FilePicker.pickFiles(
            type: FileType.custom,
            allowedExtensions: ['gguf'],
          );
          if (result.isEmpty) {
            throw const FormatException('图片模型需要配套 mmproj，导入已取消');
          }
          projection = '${directory.path}/mmproj.gguf';
          await File(result.single.path!).copy(projection);
        }
      }
      final part = File('${directory.path}/download.part');
      if (await part.exists()) await part.delete();
      final previousSelections = Map<String, dynamic>.from(
        widget.store.selected,
      );
      widget.store.models[id] = {
        'id': id,
        'name': name,
        'capabilities': capabilities,
        'format': format,
        'path': path,
        'directory': directory.path,
        'projection': projection,
      };
      await GgufContextMetadata.enrich(
        widget.store.models[id] as Map<String, dynamic>,
      );
      for (final capability in capabilities) {
        widget.store.selected.putIfAbsent(capability, () => id);
      }
      try {
        await widget.store.save();
      } catch (_) {
        widget.store.models.remove(id);
        widget.store.selected
          ..clear()
          ..addAll(previousSelections);
        rethrow;
      }
      directory = null;
      if (mounted) setState(() => status = '已导入，首次使用时验证模型兼容性');
    } catch (e) {
      if (mounted) setState(() => status = '导入失败：$e');
    } finally {
      client?.close(force: true);
      if (directory != null && await directory.exists()) {
        await directory.delete(recursive: true);
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> exportModel(String id) async {
    setState(() {
      busy = true;
      status = '正在准备完整模型包…';
    });
    try {
      final result = await exportModelToFiles(
        widget.store,
        id,
        shouldPresent: () => mounted,
      );
      if (mounted) {
        setState(
          () => status = result == null
              ? '已取消导出，应用内模型仍保留。'
              : '模型包已导出到手机文件，可备份或重新导入。',
        );
      }
    } catch (e) {
      if (mounted) setState(() => status = '导出失败：$e。应用内模型仍保留。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> importPackage() async {
    setState(() {
      busy = true;
      status = '选择应用导出的完整模型包 ZIP…';
    });
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      if (files.isEmpty) {
        if (mounted) setState(() => status = '已取消导入');
        return;
      }
      if (mounted) setState(() => status = '正在导入模型包…');
      await ModelPackage.import(widget.store, files.single.path!);
      if (mounted) setState(() => status = '模型包已导入，可在下方分配给对话、图片或语音功能。');
    } catch (e) {
      if (mounted) setState(() => status = '模型包导入失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> deleteModel(String id) async {
    if (busy) return;
    final model = widget.store.models[id];
    if (model == null) return;
    final roles = ModelRole.values
        .where((r) => widget.store.selected[r.name] == id)
        .map((r) => r.label)
        .toList();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除模型？'),
        content: SingleChildScrollView(
          child: Text(
            '将删除“${model['name']}”及应用内的模型文件和配套文件，之后可重新下载或导入。\n${roles.isEmpty ? '' : '\n正在使用：${roles.join('、')}。删除后这些功能需要重新选择模型。\n'}\n聊天和记录会保留，导入前的原始文件不会删除。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除模型'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() {
      busy = true;
      status = '正在删除模型…';
    });
    try {
      final result = await ModelLibrary(widget.store).delete(id);
      if (mounted) setState(() => status = result.warning ?? '模型已删除，可重新下载或导入。');
    } catch (e) {
      if (mounted) setState(() => status = '删除失败：$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('模型中心')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '不知道下载哪个模型？',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('浏览模型列表，选择文字、图片或语音模型，应用会下载所需文件并加入模型库。'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          await Navigator.push<void>(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ModelCatalogPage(store: widget.store),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('浏览模型列表'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '模型库',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text('下载几个，管理几个。同一个模型可以分配给多个功能，安装包不含模型。'),
        for (final entry in widget.store.models.entries)
          Card(
            child: ListTile(
              leading: const Icon(Icons.memory),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '导出到手机文件',
                    onPressed: busy ? null : () => exportModel(entry.key),
                    icon: const Icon(Icons.ios_share_outlined),
                  ),
                  IconButton(
                    tooltip: '删除模型',
                    onPressed: busy ? null : () => deleteModel(entry.key),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              title: Text(entry.value['name'] as String),
              subtitle: Text(
                LocalStore.capabilities(entry.value as Map<String, dynamic>)
                        .map((c) => ModelRole.values.byName(c).label)
                        .join(' · ') +
                    (entry.value['format'] == 'gguf'
                        ? '\n模型上下文：${entry.value['trainedContextLength'] == null ? '未识别' : '${entry.value['trainedContextLength']} tokens'} · 聊天窗口：8192 tokens'
                        : ''),
              ),
            ),
          ),
        TextButton.icon(
          onPressed: busy ? null : importPackage,
          icon: const Icon(Icons.unarchive_outlined),
          label: const Text('导入模型包 ZIP'),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: busy ? null : () => importModel(ModelRole.chat),
              child: const Text('导入 GGUF 模型'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => importModel(ModelRole.speech),
              child: const Text('导入语音模型 ZIP'),
            ),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => importModel(ModelRole.chat, download: true),
              icon: const Icon(Icons.download),
              label: const Text('自定义 GGUF 链接'),
            ),
            TextButton.icon(
              onPressed: busy
                  ? null
                  : () => importModel(ModelRole.speech, download: true),
              icon: const Icon(Icons.download),
              label: const Text('自定义语音 ZIP 链接'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (status != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(status!)),
        const Text(
          'GGUF 的图片与音频能力由用户按模型说明标记，首次推理时验证。多模态主模型需要配套 mmproj。SenseVoice / Qwen3-ASR / Whisper ONNX 用于语音识别；导入 ZIP 时自动识别模型格式。',
        ),
      ],
    ),
  );
}
