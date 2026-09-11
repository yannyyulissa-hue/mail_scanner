import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const MailScannerApp());
}

class MailScannerApp extends StatelessWidget {
  const MailScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '台中營業處掛號信掃描與歸檔',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E88E5),
          primary: const Color(0xFF1976D2),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      ),
      home: const ScannerHomePage(),
    );
  }
}

class ScanItem {
  final String fileName;
  final String filePath;
  bool isProcessing;
  bool isSuccess;
  String? errorMessage;
  Map<String, dynamic>? data;

  ScanItem({
    required this.fileName,
    required this.filePath,
    this.isProcessing = true,
    this.isSuccess = false,
    this.errorMessage,
    this.data,
  });
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  // Google Cloud Run 後端服務端點
  final String serverUrl =
      'https://mail-scanner-backend-371376741005.asia-east1.run.app/api/scan-envelope';

  // 雲端試算表連結
  final String sheetUrl =
      'https://docs.google.com/spreadsheets/d/1cPsfn_ggu01fsXG4XHxeiwS4ie5cQg4WO4QiYAW4BfE/edit?usp=sharing';

  final ImagePicker _picker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  final List<ScanItem> _scanItems = [];
  bool _isUploadingBatch = false;

  // 使用長連線 Client 複用 TCP 通道，解決 DNS 頻繁解析失敗 (Failed host lookup)
  final http.Client _httpClient = http.Client();

  @override
  void dispose() {
    _httpClient.close();
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
    if (_scanItems.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認清空', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('確定要清除畫面上所有的掃描記錄卡片嗎？\n（已寫入雲端試算表的資料不會被刪除）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
            onPressed: () {
              setState(() {
                _scanItems.clear();
              });
              Navigator.pop(ctx);
            },
            child: const Text('確定清空'),
          ),
        ],
      ),
    );
  }

  // 拍照 / 選圖：強制加入縮圖限制，原本 8MB 照片會壓縮至 300KB，大幅提升速度與穩定度
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
              title: const Text('開啟相機拍照', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? photo = await _picker.pickImage(
                  source: ImageSource.camera,
                  maxWidth: 1600,
                  maxHeight: 1600,
                  imageQuality: 85,
                );
                if (photo != null) {
                  _processImagesQueue([photo]);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: Color(0xFF1976D2)),
              title: const Text('從相簿選擇（支援多選）', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () async {
                Navigator.pop(ctx);
                final List<XFile> images = await _picker.pickMultiImage(
                  maxWidth: 1600,
                  maxHeight: 1600,
                  imageQuality: 85,
                );
                if (images.isNotEmpty) {
                  _processImagesQueue(images);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // 循序佇列：一張處理完畢後，安全間隔 1.2 秒再處理下一張，徹底避免網路擁塞
  Future<void> _processImagesQueue(List<XFile> files) async {
    setState(() {
      _isUploadingBatch = true;
    });

    for (final xfile in files) {
      final fileName = xfile.name.isNotEmpty ? xfile.name : xfile.path.split('/').last;
      final item = ScanItem(fileName: fileName, filePath: xfile.path);

      setState(() {
        _scanItems.insert(0, item);
      });

      // 傳送單張（帶雙重重試機制）
      await _uploadWithRetry(item);

      // 安全間隔 1.2 秒
      await Future.delayed(const Duration(milliseconds: 1200));
    }

    setState(() {
      _isUploadingBatch = false;
    });
  }

  // 重試機制：遭遇連線異常自動重試 2 次
  Future<void> _uploadWithRetry(ScanItem item) async {
    const int maxRetries = 2;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final success = await _uploadSingleImage(item);
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

  Future<bool> _uploadSingleImage(ScanItem item) async {
    final archiveDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    final request = http.MultipartRequest('POST', Uri.parse(serverUrl));
    request.fields['archive_date'] = archiveDateStr;
    request.files.add(
      await http.MultipartFile.fromPath('file', item.filePath),
    );

    final streamedResponse = await _httpClient.send(request).timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        throw http.ClientException('伺服器處理逾時，請檢查網路連線');
      },
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final resJson = json.decode(utf8.decode(response.bodyBytes));
      if (resJson['success'] == true) {
        setState(() {
          item.isProcessing = false;
          item.isSuccess = true;
          item.data = resJson['data'];
        });
        return true;
      } else {
        setState(() {
          item.isProcessing = false;
          item.isSuccess = false;
          item.errorMessage = resJson['error'] ?? '辨識失敗';
        });
        return false;
      }
    } else {
      setState(() {
        item.isProcessing = false;
        item.isSuccess = false;
        item.errorMessage = '伺服器代碼: ${response.statusCode}';
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
        title: Row(
          children: [
            const CorporateLogoWidget(size: 32),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '台中營業處掛號信掃描與歸檔',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                  color: Color(0xFF1A237E),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        elevation: 0.8,
        actions: [
          IconButton(
            tooltip: '開啟雲端試算表',
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
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_note, color: Color(0xFF1976D2), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    '歸檔日期: $dateStr',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF37474F),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE3F2FD),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.calendar_month, size: 15, color: Color(0xFF1976D2)),
                          SizedBox(width: 4),
                          Text(
                            '選擇日期',
                            style: TextStyle(
                              color: Color(0xFF1976D2),
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                            ? LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade500])
                            : const LinearGradient(
                                colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1976D2).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _isUploadingBatch ? Icons.hourglass_top : Icons.camera_alt,
                            color: Colors.white,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isUploadingBatch ? '辨識進行中...' : '拍攝 / 選取信封照片',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
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
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.open_in_new, color: Color(0xFF2E7D32), size: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '掃描結果 (${_scanItems.length})',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF546E7A),
                  ),
                ),
                if (_scanItems.isNotEmpty)
                  InkWell(
                    onTap: _isUploadingBatch ? null : _clearItems,
                    borderRadius: BorderRadius.circular(8),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep_outlined, size: 17, color: Color(0xFFD32F2F)),
                          SizedBox(width: 4),
                          Text(
                            '清空記錄',
                            style: TextStyle(
                              color: Color(0xFFD32F2F),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _scanItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.mark_email_read_outlined,
                              size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            '點擊上方按鈕開始掃描信封',
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _scanItems.length,
                      itemBuilder: (context, index) {
                        return _buildItemCard(_scanItems[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(ScanItem item) {
    if (item.isProcessing) {
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.blue.shade100),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  '${item.fileName} 正在辨識並同步試算表...',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (item.isSuccess) {
      final data = item.data ?? {};
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 1.5,
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
                  Expanded(
                    child: Text(
                      item.fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '已歸檔',
                      style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),
              _buildDetailRow(Icons.person, '收件人', data['recipient'] ?? '無', isHighlight: true),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.corporate_fare, '寄件人', data['sender'] ?? '無'),
              const SizedBox(height: 6),
              _buildDetailRow(
                Icons.tag,
                '掛號單號',
                data['mail_number'] ?? '無',
                valueColor: const Color(0xFF1565C0),
                isHighlight: true,
              ),
              const SizedBox(height: 6),
              _buildDetailRow(Icons.place_outlined, '收件地址', data['address'] ?? '無'),
            ],
          ),
        ),
      );
    }

    return Card(
      color: const Color(0xFFFFFBFB),
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
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
                Expanded(
                  child: Text(
                    item.fileName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '連線失敗',
                    style: TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              '錯誤原因: ${item.errorMessage}',
              style: const TextStyle(color: Color(0xFFC62828), fontSize: 12.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
    bool isHighlight = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.blueGrey.shade600),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.blueGrey.shade800,
            fontSize: 13,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF263238),
              fontSize: 13,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
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