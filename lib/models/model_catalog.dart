import 'dart:convert';

import 'catalog_data.dart';

class CatalogFile {
  CatalogFile({required this.path, required this.bytes, required this.sha256}) {
    if (bytes <= 0 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        path.startsWith('/') ||
        path.contains('\\') ||
        path.split('/').any((p) => p.isEmpty || p == '.' || p == '..')) {
      throw const FormatException('模型文件清单无效');
    }
  }
  factory CatalogFile.fromJson(Map<String, dynamic> json) => CatalogFile(
    path: json['path'] as String,
    bytes: json['bytes'] as int,
    sha256: json['sha256'] as String,
  );
  final String path, sha256;
  final int bytes;
}

class CatalogModel {
  CatalogModel({
    required this.id,
    required this.name,
    required this.repo,
    required this.revision,
    required this.format,
    required this.capabilities,
    required this.description,
    required this.variant,
    required this.files,
    this.quantization,
    this.vendor = '其他',
    this.upstream,
    this.highMemory = false,
  });
  factory CatalogModel.fromJson(Map<String, dynamic> json) => CatalogModel(
    id: json['id'] as String,
    vendor: json['vendor'] as String? ?? '其他',
    upstream: json['upstream'] as String?,
    highMemory: json['highMemory'] as bool? ?? false,
    name: json['name'] as String,
    repo: json['repo'] as String,
    revision: json['revision'] as String,
    format: json['format'] as String,
    capabilities: List<String>.from(json['capabilities'] as List),
    description: json['description'] as String,
    variant: json['variant'] as String,
    quantization: json['quantization'] as String?,
    files: (json['files'] as List)
        .map((f) => CatalogFile.fromJson(f as Map<String, dynamic>))
        .toList(),
  );
  final String id, name, repo, revision, format, description, variant;
  final String? quantization;
  final String vendor;
  final String? upstream;
  final bool highMemory;
  final List<String> capabilities;
  final List<CatalogFile> files;
  int get bytes => files.fold(0, (total, file) => total + file.bytes);
  Uri get upstreamSource => Uri.https('huggingface.co', '/${upstream ?? repo}');
  bool get communityQuantization =>
      upstream != null && repo.split('/').first != upstream!.split('/').first;
  Uri get source => Uri.https('huggingface.co', '/$repo');
  Uri downloadUrl(CatalogFile file) =>
      Uri.https('huggingface.co', '/$repo/resolve/$revision/${file.path}');
}

String modelSize(int bytes) => bytes >= 1000000000
    ? '${(bytes / 1000000000).toStringAsFixed(2)} GB'
    : '${(bytes / 1000000).toStringAsFixed(1)} MB';
final modelCatalog = (jsonDecode(catalogData) as List)
    .map((j) => CatalogModel.fromJson(j as Map<String, dynamic>))
    .toList(growable: false);
