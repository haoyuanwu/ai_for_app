import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/local_store.dart';
import '../models/catalog_installer.dart';
import '../models/model_catalog.dart';
import '../models/model_file_export.dart';

class ModelCatalogPage extends StatefulWidget {
  const ModelCatalogPage({super.key, required this.store});
  final LocalStore store;
  @override
  State<ModelCatalogPage> createState() => _ModelCatalogPageState();
}

class _ModelCatalogPageState extends State<ModelCatalogPage> {
  final installer = CatalogInstaller();
  CancelToken? token;
  String? active, message, filter, vendor;
  List<CatalogModel> get visibleModels => modelCatalog
      .where(
        (m) =>
            (filter == null || m.capabilities.contains(filter)) &&
            (vendor == null || m.vendor == vendor),
      )
      .toList();
  double? progress;
  bool get busy => active != null;
  @override
  void dispose() {
    token?.cancel('离开模型列表');
    installer.dio.close(force: true);
    super.dispose();
  }

  bool installed(CatalogModel model) => widget.store.models.values.any(
    (m) => m['catalogId'] == model.id && m['revision'] == model.revision,
  );
  Future<void> openSource(CatalogModel model, {bool upstream = false}) async {
    try {
      if (!await launchUrl(
        upstream ? model.upstreamSource : model.source,
        mode: LaunchMode.externalApplication,
      )) {
        throw StateError('无法打开模型页面');
      }
    } catch (e) {
      if (mounted) setState(() => message = '打开来源失败：$e');
    }
  }

  Future<void> download(CatalogModel model) async {
    var saveToFiles = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('下载 ${model.name}？'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<bool>(
                  initialValue: false,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '下载保存位置'),
                  items: const [
                    DropdownMenuItem(value: false, child: Text('应用内（默认）')),
                    DropdownMenuItem(
                      value: true,
                      child: Text(
                        '手机文件 + 应用内副本',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (value) =>
                      update(() => saveToFiles = value ?? false),
                ),
                const SizedBox(height: 8),
                if (saveToFiles)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      '下载完成后选择手机文件中的保存位置，导出完整 ZIP 模型包。应用内保留一份用于对话，请额外预留打包和副本的存储空间。',
                    ),
                  ),
                Text(
                  '共 ${modelSize(model.bytes)}，${model.files.length} 个文件。请预留更多运行内存和存储空间。',
                ),
                const SizedBox(height: 12),
                Text(model.description),
                if (model.highMemory)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      '高内存设备候选：模型权重之外还需要上下文、图像编码等运行内存，普通手机可能无法加载。',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '厂商：${model.vendor}\n文件发布者：${model.repo.split('/').first}',
                ),
                const SizedBox(height: 12),
                const Text(
                  '下载来源为 Hugging Face，建议使用 Wi-Fi 并保持本页打开。离开本页会取消，暂不支持断点续传。下载不等于设备已通过兼容性验证。',
                ),
                TextButton(
                  onPressed: () => openSource(model),
                  child: const Text('查看文件来源'),
                ),
                TextButton(
                  onPressed: () => openSource(model, upstream: true),
                  child: const Text('查看厂商模型与许可'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('开始下载'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    final cancel = CancelToken();
    setState(() {
      token = cancel;
      active = model.id;
      progress = 0;
      message = '正在准备 ${model.name}…';
    });
    try {
      final id = await installer.install(
        model,
        widget.store,
        cancelToken: cancel,
        onProgress: (received, total, phase) {
          if (mounted) {
            setState(() {
              progress = (received / total).clamp(0, 1);
              message = '$phase · ${modelSize(received)} / ${modelSize(total)}';
            });
          }
        },
      );
      var result = '${model.name} 已加入模型库。返回模型中心，可为多个功能共用或分别选择模型。';
      if (saveToFiles && mounted) {
        setState(() {
          progress = null;
          message = '下载完成，正在准备手机文件模型包…';
        });
        try {
          final saved = await exportModelToFiles(
            widget.store,
            id,
            shouldPresent: () => mounted,
          );
          result = saved == null
              ? '模型已下载到应用内。已取消保存到手机文件，可在模型库重新导出。'
              : '模型已保存到手机文件，应用内副本可直接使用。';
        } catch (e) {
          result = '模型已下载到应用内，但导出失败：$e。可在模型库重新导出，无需重新下载。';
        }
      }
      if (mounted) setState(() => message = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => message = e is DioException && CancelToken.isCancel(e)
              ? '已取消下载，未完成文件已清理。'
              : '下载失败：$e\n请检查网络后重试，或在电脑下载后导入。',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          active = null;
          token = null;
          progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('下载模型')),
    bottomNavigationBar: message == null && !busy
        ? null
        : SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surfaceContainer,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (busy) LinearProgressIndicator(value: progress),
                  if (message != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 100),
                      child: SingleChildScrollView(child: Text(message!)),
                    ),
                  if (busy)
                    TextButton(
                      onPressed: () => token?.cancel('用户取消'),
                      child: const Text('取消下载'),
                    ),
                ],
              ),
            ),
          ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '选好模型，再开始对话',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          '仅展示国内厂商模型。首次体验可先选 Qwen3.5 0.8B；模型下载到本机，安装包不含模型，同一模型可分配给多个功能。',
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: 'all',
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '厂商',
            border: OutlineInputBorder(),
          ),
          items: [
            const DropdownMenuItem(value: 'all', child: Text('全部厂商')),
            for (final name in modelCatalog.map((m) => m.vendor).toSet())
              DropdownMenuItem(value: name, child: Text(name)),
          ],
          onChanged: (name) =>
              setState(() => vendor = name == 'all' ? null : name),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in {
              'all': '全部',
              'chat': '文字',
              'vision': '图片',
              'speech': '语音',
            }.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: filter == (entry.key == 'all' ? null : entry.key),
                onSelected: (_) => setState(
                  () => filter = entry.key == 'all' ? null : entry.key,
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        for (final model in visibleModels) modelCard(model),
        if (visibleModels.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('该厂商暂无此用途的模型，请切换筛选。'),
          ),
        if (filter == null || filter == 'speech')
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '更多语音与多模态模型',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'SenseVoice 和 Qwen3-ASR 可从上方下载，用于本地语音转文字。FireRedASR 及其他未适配的模型暂不提供下载。',
                  ),
                  SizedBox(height: 8),
                  Text(
                    'MiniCPM-o、Qwen2.5-Omni、Fun-Audio-Chat 的完整语音能力，以及 Qwen3-TTS、CosyVoice、GPT-SoVITS、MNN-Sana 生图，需要另行接入对应引擎。',
                  ),
                ],
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text(
            '列表文件信息核对于 2026-11-04。需要访问 Hugging Face；下载大小不等于运行内存。列表为端侧候选，尚未逐一真机验收；中文表现、速度和兼容性以设备测试为准。自动记录和历史查询也取决于模型的工具调用能力。',
          ),
        ),
      ],
    ),
  );
  Widget modelCard(CatalogModel model) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(model.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final capability in model.capabilities)
                Chip(label: Text(ModelRole.values.byName(capability).label)),
              Chip(label: Text(modelSize(model.bytes))),
              Chip(label: Text(model.vendor)),
              if (model.highMemory) const Chip(label: Text('高内存设备')),
              if (model.communityQuantization)
                const Chip(label: Text('社区转换 / 量化')),
            ],
          ),
          Text(model.description),
          const SizedBox(height: 8),
          Text(model.variant, style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                onPressed: busy || installed(model)
                    ? null
                    : () => download(model),
                icon: Icon(
                  installed(model) ? Icons.check : Icons.download_outlined,
                ),
                label: Text(
                  installed(model) ? '已下载' : '下载 ${modelSize(model.bytes)}',
                ),
              ),
              TextButton(
                onPressed: () => openSource(model),
                child: const Text('模型来源'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
