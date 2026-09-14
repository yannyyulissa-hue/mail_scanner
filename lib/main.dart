import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UnifiedScannerApp());
}

class UnifiedScannerApp extends StatelessWidget {
  const UnifiedScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '郵件與公文掃描',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1976D2),
          primary: const Color(0xFF1976D2),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      ),
      home: const MainNavigationShell(),
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    MailScannerView(),
    DocScannerView(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.mark_email_read_outlined),
            selectedIcon: Icon(Icons.mark_email_read, color: Color(0xFF1976D2)),
            label: '掛號信件歸檔',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_edu_outlined),
            selectedIcon: Icon(Icons.history_edu, color: Color(0xFF2E7D32)),
            label: '公文函文收文',
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 分頁一：掛號信件歸檔 (支援單拍、正反連拍、相簿多選批次)
// =============================================================
class MailItem {
  final String fileName;
  bool isProcessing;
  bool isSuccess;
  String? errorMessage;
  Map<String, dynamic>? data;

  MailItem({
    required this.fileName,
    this.isProcessing = true,
    this.isSuccess = false,
    this.errorMessage,
    this.data,
  });
}

class MailScannerView extends StatefulWidget {
  const MailScannerView({super.key});

  @override
  State<MailScannerView> createState() => _MailScannerViewState();
}

class _MailScannerViewState extends State<MailScannerView> {
  final String batchServerUrl =
      'https://mail-scanner-backend-371376741005.asia-east1.run.app/api/scan-envelopes-batch';

  final String sheetUrl =
      'https://docs.google.com/spreadsheets/d/1cPsfn_ggu01fsXG4XHxeiwS4ie5cQg4WO4QiYAW4BfE/edit?usp=sharing';

  final ImagePicker _picker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  final List<MailItem> _items = [];
  bool _isUploadingBatch = false;
  final http.Client _httpClient = http.Client();

  @override
  void dispose() {
    _httpClient.close();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _launchSheetUrl() async {
    final uri = Uri.parse(sheetUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法開啟試算表網址')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _clearItems() {
    if (_items.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認清空', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('確定要清除畫面上的信件掃描卡片嗎？\n（已寫入試算表的紀錄不會受影響）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1976D2)),
            onPressed: () {
              setState(() => _items.clear());
              Navigator.pop(ctx);
            },
            child: const Text('確定清空'),
          ),
        ],
      ),
    );
  }

  // 拍照流程：支援單面拍照或連拍背面條碼
  Future<void> _startCameraWorkflow() async {
    final XFile? frontPhoto = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 70,
    );

    if (frontPhoto == null) return;
    if (!mounted) return;

    final bool? needBackSide = await showModalBottomSheet<bool>(
      context: context,
      barrierColor: Colors.black54,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF1976D2), size: 24),
                  SizedBox(width: 10),
                  Text('已拍完第 1 張', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '該信件是否需要拍攝背面條碼？',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFF1976D2)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.send_rounded, color: Color(0xFF1976D2)),
                      label: const Text('單面直接歸檔', style: TextStyle(color: Color(0xFF1976D2), fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.pop(ctx, false),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: const Color(0xFF1976D2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.flip_to_back_rounded),
                      label: const Text('加拍背面條碼', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => Navigator.pop(ctx, true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (needBackSide == true) {
      final XFile? backPhoto = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 70,
      );

      if (backPhoto != null) {
        _processBatchInOneRequest([frontPhoto, backPhoto]);
      } else {
        _processBatchInOneRequest([frontPhoto]);
      }
    } else if (needBackSide == false) {
      _processBatchInOneRequest([frontPhoto]);
    }
  }

  Future<void> _pickAndProcessImages() async {
    if (_isUploadingBatch) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF1976D2)),
              title: const Text('開啟相機拍照（支援單/雙面連拍）', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(ctx);
                _startCameraWorkflow();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF1976D2)),
              title: const Text('從相簿選取（支援多選、正反面自動合併）', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final List<XFile> images = await _picker.pickMultiImage(
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 70,
                );
                if (images.isNotEmpty) {
                  _processBatchInOneRequest(images);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // 真正將整批照片打包在同一個 MultipartRequest 傳送
  Future<void> _processBatchInOneRequest(List<XFile> files) async {
    setState(() => _isUploadingBatch = true);
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    final processingItem = MailItem(
      fileName: '批次處理中 (${files.length} 張相片，比對合併中...)',
      isProcessing: true,
    );
    setState(() => _items.insert(0, processingItem));

    try {
      final archiveDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final uri = Uri.parse(batchServerUrl);
      final request = http.MultipartRequest('POST', uri);
      request.fields['archive_date'] = archiveDateStr;

      // 將每張檔案依序加入請求
      for (final xfile in files) {
        request.files.add(await http.MultipartFile.fromPath('files', xfile.path));
      }

      final streamed = await _httpClient.send(request).timeout(
        const Duration(seconds: 120),
        onTimeout: () => throw http.ClientException('連線逾時，後端運算中'),
      );
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 200) {
        final jsonMap = json.decode(utf8.decode(res.bodyBytes));
        if (jsonMap['success'] == true) {
          setState(() {
            _items.remove(processingItem);
            final List results = jsonMap['data'] ?? [];
            for (var d in results) {
              _items.insert(
                0,
                MailItem(
                  fileName: d['file_name'] ?? '信件',
                  isProcessing: false,
                  isSuccess: true,
                  data: d,
                ),
              );
            }
          });
        } else {
          setState(() {
            processingItem.isProcessing = false;
            processingItem.isSuccess = false;
            processingItem.errorMessage = jsonMap['error'] ?? '批次處理失敗';
          });
        }
      } else {
        setState(() {
          processingItem.isProcessing = false;
          processingItem.isSuccess = false;
          processingItem.errorMessage = '伺服器代碼: ${res.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        processingItem.isProcessing = false;
        processingItem.isSuccess = false;
        processingItem.errorMessage = e.toString();
      });
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      setState(() => _isUploadingBatch = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: Row(
          children: [
            const CorporateLogoWidget(size: 32),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '郵件與公文掃描 - 掛號信件',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1A237E)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.8,
        actions: [
          IconButton(
            tooltip: '開啟掛號信試算表',
            icon: const Icon(Icons.table_chart, color: Color(0xFF2E7D32)),
            onPressed: _launchSheetUrl,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note, color: Color(0xFF1976D2), size: 20),
                  const SizedBox(width: 8),
                  Text('歸檔日期: $dateStr', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        children: [
                          Icon(Icons.calendar_month, size: 15, color: Color(0xFF1976D2)),
                          SizedBox(width: 4),
                          Text('選擇日期', style: TextStyle(color: Color(0xFF1976D2), fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: _isUploadingBatch ? null : _pickAndProcessImages,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: _isUploadingBatch
                            ? LinearGradient(colors: [Colors.grey.shade500, Colors.grey.shade600])
                            : const LinearGradient(colors: [Color(0xFF1976D2), Color(0xFF0D47A1)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isUploadingBatch ? Icons.wb_sunny_outlined : Icons.camera_alt, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isUploadingBatch ? '辨識合併中 (常亮防休眠)' : '拍攝 / 選取信封照片',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: _launchSheetUrl,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: const Icon(Icons.open_in_new, color: Color(0xFF2E7D32), size: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('掃描結果 (${_items.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF546E7A))),
                if (_items.isNotEmpty)
                  InkWell(
                    onTap: _isUploadingBatch ? null : _clearItems,
                    child: const Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, size: 17, color: Color(0xFFD32F2F)),
                        SizedBox(width: 4),
                        Text('清空列表', style: TextStyle(color: Color(0xFFD32F2F), fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_email_read_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('點擊上方按鈕拍照或多選相片（支援正反面自動合併）', style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) => _buildMailCard(_items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMailCard(MailItem item) {
    if (item.isProcessing) {
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
              const SizedBox(width: 14),
              Expanded(child: Text(item.fileName)),
            ],
          ),
        ),
      );
    }

    if (item.isSuccess) {
      final d = item.data ?? {};
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFA5D6A7), width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.fileName, style: const TextStyle(fontWeight: FontWeight.bold))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                    child: const Text('已歸檔', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                ],
              ),
              const Divider(height: 20),
              _buildRow(Icons.person, '收件人', d['recipient'] ?? '無', isHighlight: true),
              const SizedBox(height: 6),
              _buildRow(Icons.corporate_fare, '寄件人', d['sender'] ?? '無'),
              const SizedBox(height: 6),
              _buildRow(Icons.tag, '掛號單號', d['mail_number'] ?? '無', valueColor: const Color(0xFF1565C0), isHighlight: true),
              const SizedBox(height: 6),
              _buildRow(Icons.place_outlined, '收件地址', d['address'] ?? '無'),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFFFFFBFB),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFCDD2), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(item.fileName, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const Divider(height: 20),
            Text('錯誤: ${item.errorMessage}', style: const TextStyle(color: Color(0xFFC62828), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String value, {Color? valueColor, bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey.shade600),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal)),
        Expanded(child: Text(value, style: TextStyle(color: valueColor, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal))),
      ],
    );
  }
}

// =============================================================
// 分頁二：公文函文收文
// =============================================================
class DocItem {
  final String fileName;
  final String filePath;
  bool isProcessing;
  bool isSuccess;
  String? errorMessage;
  Map<String, dynamic>? data;

  DocItem({
    required this.fileName,
    required this.filePath,
    this.isProcessing = true,
    this.isSuccess = false,
    this.errorMessage,
    this.data,
  });
}

class DocScannerView extends StatefulWidget {
  const DocScannerView({super.key});

  @override
  State<DocScannerView> createState() => _DocScannerViewState();
}

class _DocScannerViewState extends State<DocScannerView> {
  final String docServerUrl =
      'https://mail-scanner-backend-371376741005.asia-east1.run.app/api/scan-official-doc';

  final String docSheetUrl =
      'https://docs.google.com/spreadsheets/d/1JRaB8g6VCWo-5ohdCphfwFA1IcooxlmH3puizsVMej8/edit?usp=drive_link';

  final ImagePicker _picker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  final List<DocItem> _items = [];
  bool _isUploadingBatch = false;
  final http.Client _httpClient = http.Client();

  @override
  void dispose() {
    _httpClient.close();
    WakelockPlus.disable();
    super.dispose();
  }

  Future<void> _launchSheetUrl() async {
    final uri = Uri.parse(docSheetUrl);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法開啟公文登記簿網址')),
        );
      }
    }
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void _clearItems() {
    if (_items.isEmpty) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認清空', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('確定要清除畫面上的公文掃描卡片嗎？\n（已寫入試算表的紀錄不會受影響）'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () {
              setState(() => _items.clear());
              Navigator.pop(ctx);
            },
            child: const Text('確定清空'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndProcessImages() async {
    if (_isUploadingBatch) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined, color: Color(0xFF2E7D32)),
              title: const Text('拍攝公文首頁', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? photo = await _picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 70,
                );
                if (photo != null) _processDocQueue([photo]);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF2E7D32)),
              title: const Text('從相簿選取（支援多選）', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final List<XFile> images = await _picker.pickMultiImage(
                  maxWidth: 1024,
                  maxHeight: 1024,
                  imageQuality: 70,
                );
                if (images.isNotEmpty) _processDocQueue(images);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processDocQueue(List<XFile> files) async {
    setState(() => _isUploadingBatch = true);
    try {
      await WakelockPlus.enable();
    } catch (_) {}

    try {
      for (final xfile in files) {
        final fileName = xfile.name.isNotEmpty ? xfile.name : xfile.path.split('/').last;
        final item = DocItem(fileName: fileName, filePath: xfile.path);
        setState(() => _items.insert(0, item));

        await _uploadDocWithRetry(item);
        await Future.delayed(const Duration(milliseconds: 1200));
      }
    } finally {
      try {
        await WakelockPlus.disable();
      } catch (_) {}
      setState(() => _isUploadingBatch = false);
    }
  }

  Future<void> _uploadDocWithRetry(DocItem item) async {
    const int maxRetries = 2;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final success = await _uploadDocSingle(item);
        if (success) return;
      } catch (e) {
        if (attempt < maxRetries) {
          await Future.delayed(const Duration(seconds: 2));
        } else {
          setState(() {
            item.isProcessing = false;
            item.isSuccess = false;
            item.errorMessage = e.toString();
          });
        }
      }
    }
  }

  Future<bool> _uploadDocSingle(DocItem item) async {
    final receiveDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final request = http.MultipartRequest('POST', Uri.parse(docServerUrl));
    request.fields['receive_date'] = receiveDateStr;
    request.files.add(await http.MultipartFile.fromPath('file', item.filePath));

    final streamed = await _httpClient.send(request).timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw http.ClientException('連線逾時，請檢查伺服器連線'),
    );
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 200) {
      final jsonMap = json.decode(utf8.decode(res.bodyBytes));
      if (jsonMap['success'] == true) {
        setState(() {
          item.isProcessing = false;
          item.isSuccess = true;
          item.data = jsonMap['data'];
        });
        return true;
      } else {
        setState(() {
          item.isProcessing = false;
          item.isSuccess = false;
          item.errorMessage = jsonMap['error'] ?? '公文辨識失敗';
        });
        return false;
      }
    } else {
      setState(() {
        item.isProcessing = false;
        item.isSuccess = false;
        item.errorMessage = '伺服器代碼: ${res.statusCode}';
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 12,
        title: const Row(
          children: [
            Icon(Icons.history_edu_rounded, color: Color(0xFF2E7D32), size: 28),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '郵件與公文掃描 - 公文登記',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Color(0xFF1B5E20)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.8,
        actions: [
          IconButton(
            tooltip: '開啟公文登記簿',
            icon: const Icon(Icons.table_chart, color: Color(0xFF2E7D32)),
            onPressed: _launchSheetUrl,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 3)),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 8),
                  Text('受月日 (收文日): $dateStr', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        children: [
                          Icon(Icons.edit_calendar, size: 15, color: Color(0xFF2E7D32)),
                          SizedBox(width: 4),
                          Text('選擇日期', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 12.5, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: InkWell(
                    onTap: _isUploadingBatch ? null : _pickAndProcessImages,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        gradient: _isUploadingBatch
                            ? LinearGradient(colors: [Colors.grey.shade500, Colors.grey.shade600])
                            : const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)]),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_isUploadingBatch ? Icons.wb_sunny_outlined : Icons.document_scanner, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _isUploadingBatch ? '辨識歸檔中 (防休眠保護中)' : '拍攝 / 選取公文相片',
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 1,
                  child: InkWell(
                    onTap: _launchSheetUrl,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFA5D6A7)),
                      ),
                      child: const Icon(Icons.open_in_new, color: Color(0xFF2E7D32), size: 20),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('收文登記 (${_items.length})', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF546E7A))),
                if (_items.isNotEmpty)
                  InkWell(
                    onTap: _isUploadingBatch ? null : _clearItems,
                    child: const Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, size: 17, color: Color(0xFF2E7D32)),
                        SizedBox(width: 4),
                        Text('清空列表', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.article_outlined, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text('請拍攝或選取公文首頁照片進行收文歸檔', style: TextStyle(color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (ctx, i) => _buildDocCard(_items[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocCard(DocItem item) {
    if (item.isProcessing) {
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF2E7D32))),
              const SizedBox(width: 14),
              Expanded(child: Text('${item.fileName} 正在提取公文資料並登記...')),
            ],
          ),
        ),
      );
    }

    if (item.isSuccess) {
      final d = item.data ?? {};
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFA5D6A7), width: 1.2),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF2E7D32), size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.fileName, style: const TextStyle(fontWeight: FontWeight.bold))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                    child: const Text('已收文歸檔', style: TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                ],
              ),
              const Divider(height: 20),
              _buildRow(Icons.business_outlined, '受文單位', d['recipient_unit'] ?? '無', isHighlight: true),
              const SizedBox(height: 6),
              _buildRow(Icons.account_balance, '發文機關', d['issuing_agency'] ?? '無', isHighlight: true),
              const SizedBox(height: 6),
              _buildRow(Icons.category_outlined, '文別', d['doc_type'] ?? '函'),
              const SizedBox(height: 6),
              _buildRow(Icons.tag, '發文字號', d['doc_number'] ?? '無', valueColor: const Color(0xFF2E7D32), isHighlight: true),
              const SizedBox(height: 6),
              _buildRow(Icons.subject, '事由 / 主旨', d['subject'] ?? '無', valueColor: const Color(0xFF37474F)),
              const SizedBox(height: 6),
              _buildRow(Icons.attach_file, '附件', d['attachment'] ?? '無'),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFFFFFBFB),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFFFCDD2), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error_outline, color: Color(0xFFC62828), size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(item.fileName, style: const TextStyle(fontWeight: FontWeight.bold))),
              ],
            ),
            const Divider(height: 20),
            Text('錯誤: ${item.errorMessage}', style: const TextStyle(color: Color(0xFFC62828), fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(IconData icon, String label, String value, {Color? valueColor, bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey.shade600),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal)),
        Expanded(child: Text(value, style: TextStyle(color: valueColor, fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal))),
      ],
    );
  }
}

class CorporateLogoWidget extends StatelessWidget {
  final double size;
  const CorporateLogoWidget({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.15,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: size * 0.52,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF00A0E9),
                borderRadius: BorderRadius.all(Radius.elliptical(100, 50)),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: size * 0.52,
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFF009944),
                borderRadius: BorderRadius.all(Radius.elliptical(100, 50)),
              ),
            ),
          ),
          Text(
            'H',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.72,
              fontWeight: FontWeight.w900,
              fontFamily: 'serif',
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}