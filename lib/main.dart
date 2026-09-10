import 'dart:convert';
import 'dart:io';
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
  final String serverUrl = 'http://192.168.1.73:8000/api/scan-envelope';
  final ImagePicker _picker = ImagePicker();

  DateTime _selectedDate = DateTime.now();
  bool _isProcessing = false;
  String _statusMessage = '';
  List<Map<String, dynamic>> _scanResults = [];

  // 選擇日期
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

  // 底部彈出選單：拍照或相簿多選
  void _showImageSourcePicker() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const conscienceText('立即拍照'),
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

  // 相簿多選
  Future<void> _pickMultipleImages() async {
    final List<XFile> images = await _picker.pickMultiImage();
    if (images.isNotEmpty) {
      await _uploadAndProcessImages(images);
    }
  }

  // 逐張上傳與辨識
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
        _statusMessage = '正在處理第 ${i + 1} / ${files.length} 張照片...';
      });

      try {
        var request = http.MultipartRequest('POST', Uri.parse(serverUrl));
        request.fields['archive_date'] = dateString;
        request.files.add(await http.MultipartFile.fromPath('file', file.path));

        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          final resultData = jsonDecode(utf8.decode(response.bodyBytes));
          _scanResults.add({
            'file': file.name,
            'status': '成功',
            'data': resultData,
          });
        } else {
          _scanResults.add({
            'file': file.name,
            'status': '失敗 (${response.statusCode})',
            'data': response.body,
          });
        }
      } catch (e) {
        _scanResults.add({
          'file': file.name,
          'status': '連線失敗',
          'data': e.toString(),
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
            // 歸檔日期列
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
            const SizedBox(height: 16),

            // 操作按鈕
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _isProcessing ? null : _showImageSourcePicker,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  _isProcessing ? '正在處理中...' : '開啟相機或選取信封照片',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 處理中進度指示
            if (_isProcessing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(_statusMessage, style: const TextStyle(color: Colors.blueGrey)),
              const SizedBox(height: 16),
            ],

            // 辨識結果展示列表
            Expanded(
              child: _scanResults.isEmpty
                  ? Center(child: Text(_statusMessage.isEmpty ? '尚無辨識結果' : _statusMessage))
                  : ListView.builder(
                      itemCount: _scanResults.length,
                      itemBuilder: (ctx, index) {
                        final item = _scanResults[index];
                        final bool isSuccess = item['status'] == '成功';
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          color: isSuccess ? Colors.green.shade50 : Colors.red.shade50,
                          child: ListTile(
                            leading: Icon(
                              isSuccess ? Icons.check_circle : Icons.error,
                              color: isSuccess ? Colors.green : Colors.red,
                            ),
                            title: Text('檔案: ${item['file']} (${item['status']})'),
                            subtitle: Text(
                              '內容: ${item['data'].toString()}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
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
}

class conscienceText extends StatelessWidget {
  final String text;
  const conscienceText(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Text(text);
}