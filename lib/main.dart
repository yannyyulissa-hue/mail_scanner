import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

void main() {
  runApp(const MailScannerApp());
}

class MailScannerApp extends StatelessWidget {
  const MailScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '企業掛號信掃描與歸檔',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF7F6FB),
      ),
      home: const ScannerHomePage(),
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({super.key});

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

// 掃描卡片項目狀態物件
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

class _ScannerHomePageState extends State<ScannerHomePage> {
  // 正式 Cloud Run 後端網址
  final String serverUrl =
      'https://mail-scanner-backend-371376741005.asia-east1.run.app/api/scan-envelope';

  final ImagePicker _picker = ImagePicker();
  DateTime _selectedDate = DateTime.now();
  final List<ScanItem> _scanItems = [];
  bool _isUploadingBatch = false;

  // 選擇歸檔日期
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

  // 選取照片（支援多張選取與相機拍照）
  Future<void> _pickAndProcessImages() async {
    if (_isUploadingBatch) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('拍照'),
              onTap: () async {
                Navigator.pop(ctx);
                final XFile? photo =
                    await _picker.pickImage(source: ImageSource.camera);
                if (photo != null) {
                  _processImagesQueue([photo]);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('從相簿選擇（可多選）'),
              onTap: () async {
                Navigator.pop(ctx);
                final List<XFile> images = await _picker.pickMultiImage();
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

  // 關鍵佇列核心：循序處理每一張照片，徹底避免併發斷線
  Future<void> _processImagesQueue(List<XFile> files) async {
    setState(() {
      _isUploadingBatch = true;
    });

    for (final xfile in files) {
      final fileName = xfile.name.isNotEmpty ? xfile.name : xfile.path.split('/').last;
      final item = ScanItem(fileName: fileName, filePath: xfile.path);

      // 新增至頂部顯示
      setState(() {
        _scanItems.insert(0, item);
      });

      // 逐張呼叫上傳與辨識
      await _uploadSingleImage(item);
    }

    setState(() {
      _isUploadingBatch = false;
    });
  }

  // 單張上傳並帶有 90 秒逾時保護
  Future<void> _uploadSingleImage(ScanItem item) async {
    final archiveDateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    try {
      final request = http.MultipartRequest('POST', Uri.parse(serverUrl));
      request.fields['archive_date'] = archiveDateStr;
      request.files.add(
        await http.MultipartFile.fromPath('file', item.filePath),
      );

      // 設定 90 秒連線超時
      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 90),
        onTimeout: () {
          throw http.ClientException('連線逾時 (90秒)，請檢查網路或稍後重試');
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
        } else {
          setState(() {
            item.isProcessing = false;
            item.isSuccess = false;
            item.errorMessage = resJson['error'] ?? '伺服器辨識失敗';
          });
        }
      } else {
        setState(() {
          item.isProcessing = false;
          item.isSuccess = false;
          item.errorMessage = 'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        });
      }
    } catch (e) {
      setState(() {
        item.isProcessing = false;
        item.isSuccess = false;
        item.errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '企業掛號信掃描與歸檔',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
        ),
        backgroundColor: const Color(0xFFD6BBFC),
        elevation: 0,
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            // 歸檔日期選擇器
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Text(
                    '歸檔日期: $dateStr',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C3E50),
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _pickDate,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F0FA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.calendar_today_outlined,
                              size: 16, color: Color(0xFF5E35B1)),
                          SizedBox(width: 6),
                          Text(
                            '選擇日期',
                            style: TextStyle(
                              color: Color(0xFF5E35B1),
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
            ),
            const SizedBox(height: 12),

            // 開啟相機/選取相片按鈕
            InkWell(
              onTap: _isUploadingBatch ? null : _pickAndProcessImages,
              borderRadius: BorderRadius.circular(24),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _isUploadingBatch
                      ? Colors.grey.shade300
                      : const Color(0xFFF1EBFB),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: _isUploadingBatch
                        ? Colors.grey.shade400
                        : const Color(0xFFD6BBFC),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.camera_alt_outlined,
                      color: _isUploadingBatch
                          ? Colors.grey.shade600
                          : const Color(0xFF5E35B1),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _isUploadingBatch ? '正在批次處理中，請稍候...' : '開啟相機或選取信封照片',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: _isUploadingBatch
                            ? Colors.grey.shade600
                            : const Color(0xFF5E35B1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 結果列表區
            Expanded(
              child: _scanItems.isEmpty
                  ? Center(
                      child: Text(
                        '尚未掃描任何信封',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _scanItems.length,
                      itemBuilder: (context, index) {
                        final item = _scanItems[index];
                        return _buildItemCard(item);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 建立結果卡片（依據處理中、成功、失敗呈現對應配色）
  Widget _buildItemCard(ScanItem item) {
    if (item.isProcessing) {
      return Card(
        color: Colors.white,
        margin: const EdgeInsets.only(bottom: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.purple.shade100),
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
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '${item.fileName} 正在辨識與歸檔中...',
                  style: const TextStyle(fontWeight: FontWeight.w600),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF81C784), width: 1.5),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 頂部檔名與成功徽章
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.fileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '成功',
                      style: TextStyle(
                        color: Color(0xFF2E7D32),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),

              // 收件人
              _buildDetailRow(
                icon: Icons.person_outline,
                label: '收件人',
                value: data['recipient'] ?? '無',
                isBold: true,
              ),
              const SizedBox(height: 6),

              // 寄件人
              _buildDetailRow(
                icon: Icons.business_outlined,
                label: '寄件人',
                value: data['sender'] ?? '無',
              ),
              const SizedBox(height: 6),

              // 掛號單號
              _buildDetailRow(
                icon: Icons.confirmation_number_outlined,
                label: '掛號單號',
                value: data['mail_number'] ?? '無',
                valueColor: const Color(0xFF1565C0),
                isBold: true,
              ),
              const SizedBox(height: 6),

              // 收件地址
              _buildDetailRow(
                icon: Icons.location_on_outlined,
                label: '收件地址',
                value: data['address'] ?? '無',
              ),
            ],
          ),
        ),
      );
    }

    // 失敗狀態卡片
    return Card(
      color: const Color(0xFFFFF8F8),
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEF9A9A), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.error, color: Color(0xFFE53935), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.fileName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '連線失敗',
                    style: TextStyle(
                      color: Color(0xFFC62828),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            Text(
              '錯誤原因: ${item.errorMessage}',
              style: const TextStyle(color: Color(0xFFD32F2F), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  // 輔助行排版
  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: Colors.grey.shade700),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey.shade800,
            fontSize: 13.5,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF2C3E50),
              fontSize: 13.5,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }
}