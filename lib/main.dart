import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const ScanHomePage(),
    );
  }
}

class ScanHomePage extends StatefulWidget {
  const ScanHomePage({super.key});

  @override
  State<ScanHomePage> createState() => _ScanHomePageState();
}

class _ScanHomePageState extends State<ScanHomePage> {
  // 電腦後端 API 位址
  final String serverUrl = 'http://192.168.1.73:8000/api/scan-envelope';
  final ImagePicker _picker = ImagePicker();

  DateTime _selectedDate = DateTime.now();
  bool _isProcessing = false;
  String _statusMessage = '';
  final List<Map<String, dynamic>> _scanResults = [];

  // 日期選擇器
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // 底部選單：拍照或相簿多選
  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('開啟相機拍照'),
              onTap: () {
                Navigator.of(ctx).pop();
                _captureFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('從相簿多選相片'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickMultipleImages();
              },
            ),
          ],
        ),
      ),
    );
  }

  // 相機拍攝單張
  Future<void> _captureFromCamera() async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) {
      await _uploadAndProcessImages([photo]);
    }
  }

  // 相簿多選照片
  Future<void> _pickMultipleImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      await _uploadAndProcessImages(images);
    }
  }

  // 逐張上傳至後端進行辨識與存檔
  Future<void> _uploadAndProcessImages(List<XFile> files) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = '準備上傳...';
      _scanResults.clear();
    });

    final String dateString = DateFormat('yyyy-MM-dd').format(_selectedDate);

    for (int i = 0; i < files.length; i++) {
      final file = files[i];
      setState(() {
        _statusMessage = '正在辨識第 ${i + 1} / ${files.length} 張照片...';
      });

      try {
        var request = http.MultipartRequest('POST', Uri.parse(serverUrl));
        request.fields['archive_date'] = dateString;
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final resJson = jsonDecode(utf8.decode(response.bodyBytes));
          final bool isSuccess = resJson['success'] == true;

          _scanResults.add({
            'file': file.name,
            'status': isSuccess ? '成功' : '失敗',
            'data': resJson['data'],
            'error': resJson['error'] ?? '',
          });
        } else {
          _scanResults.add({
            'file': file.name,
            'status': '失敗',
            'data': null,
            'error': 'HTTP ${response.statusCode}: ${response.body}',
          });
        }
      } catch (e) {
        _scanResults.add({
          'file': file.name,
          'status': '連線失敗',
          'data': null,
          'error': e.toString(),
        });
      }
    }

    setState(() {
      _isProcessing = false;
      _statusMessage = '全數處理完成！共 ${files.length} 張';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('企業掛號信掃描與歸檔'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 日期選擇區塊
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '歸檔日期: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _selectDate(context),
                      icon: const Icon(Icons.calendar_today, size: 18),
                      label: const Text('選擇日期'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 操作按鈕
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _showImageSourcePicker,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  _isProcessing ? '正在辨識處理中...' : '開啟相機或選取信封照片',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 進度指示條
            if (_isProcessing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_statusMessage, style: const TextStyle(color: Colors.blueGrey, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
            ],

            // 辨識結果清單
            Expanded(
              child: _scanResults.isEmpty
                  ? Center(child: Text(_statusMessage.isEmpty ? '尚無掃描資料' : _statusMessage))
                  : ListView.builder(
                      itemCount: _scanResults.length,
                      itemBuilder: (ctx, index) {
                        final item = _scanResults[index];
                        final bool isSuccess = item['status'] == '成功';
                        final Map<String, dynamic>? info = item['data'];

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isSuccess ? Colors.green.shade300 : Colors.red.shade300,
                              width: 1.5,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(14.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // 頂部檔名與狀態標籤
                                Row(
                                  children: [
                                    Icon(
                                      isSuccess ? Icons.check_circle : Icons.error,
                                      color: isSuccess ? Colors.green : Colors.red,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        item['file'],
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: isSuccess ? Colors.green.shade100 : Colors.red.shade100,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        item['status'],
                                        style: TextStyle(
                                          color: isSuccess ? Colors.green.shade800 : Colors.red.shade800,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 18),

                                // 詳細辨識內容
                                if (isSuccess && info != null) ...[
                                  _buildInfoRow(Icons.person, '收件人', info['recipient'] ?? '無'),
                                  const SizedBox(height: 6),
                                  _buildInfoRow(Icons.business, '寄件人', info['sender'] ?? '無'),
                                  const SizedBox(height: 6),
                                  _buildInfoRow(Icons.confirmation_number, '掛號單號', info['mail_number'] ?? '無', isHighlight: true),
                                  const SizedBox(height: 6),
                                  _buildInfoRow(Icons.location_on, '收件地址', info['address'] ?? '無'),
                                ] else ...[
                                  Text(
                                    '錯誤原因: ${item['error']}',
                                    style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // 結構化單行顯示小工具
  Widget _buildInfoRow(IconData icon, String label, String value, {bool isHighlight = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: isHighlight ? Colors.blueAccent : Colors.grey.shade700),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
              color: isHighlight ? Colors.blue.shade900 : Colors.black87,
            ),
          ),
        ),
      ],
    );
  }
}