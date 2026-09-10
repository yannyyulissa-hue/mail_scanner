import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

void main() {
  runApp(const EnvelopeScannerApp());
}

class EnvelopeScannerApp extends StatelessWidget {
  const EnvelopeScannerApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '企業掛號信掃描與歸檔',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const ScannerHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScannerHomePage extends StatefulWidget {
  const ScannerHomePage({Key? key}) : super(key: key);

  @override
  State<ScannerHomePage> createState() => _ScannerHomePageState();
}

class _ScannerHomePageState extends State<ScannerHomePage> {
  DateTime selectedDate = DateTime.now();
  bool isLoading = false;
  String? errorMessage;
  Map<String, dynamic>? scanResult;

  // 彈出日期選擇視窗
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != selectedDate) {
      setState(() {
        selectedDate = picked;
      });
    }
  }

  // 選擇圖片並上傳至 FastAPI 後端
  Future<void> _pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
      scanResult = null;
    });

    try {
      // 讀取圖片位元組
      Uint8List imageBytes = await image.readAsBytes();

      // 格式化日期字串 (YYYY-MM-DD)
      String formattedDate = "${selectedDate.year.toString().padLeft(4, '0')}-"
                             "${selectedDate.month.toString().padLeft(2, '0')}-"
                             "${selectedDate.day.toString().padLeft(2, '0')}";

      // 建立 Multipart 請求
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.1.73:8000/api/scan-envelope'),
      );

      request.fields['archive_date'] = formattedDate;
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: image.name,
        ),
      );

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          scanResult = data['data'];
        });
      } else {
        var errorData = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          errorMessage = errorData['detail'] ?? '伺服器發生未知錯誤 (代碼: ${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = '連線錯誤: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate = "${selectedDate.year.toString().padLeft(4, '0')}-"
                           "${selectedDate.month.toString().padLeft(2, '0')}-"
                           "${selectedDate.day.toString().padLeft(2, '0')}";

    return Scaffold(
      appBar: AppBar(
        title: const Text('企業掛號信掃描與歸檔'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 日期選擇區塊
                Card(
                  elevation: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '歸檔日期: $formattedDate',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        ElevatedButton.icon(
                          onPressed: isLoading ? null : () => _selectDate(context),
                          icon: const Icon(Icons.calendar_today),
                          label: const Text('選擇日期'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // 2. 拍照/選擇圖片按鈕
                ElevatedButton.icon(
                  onPressed: isLoading ? null : _pickAndUploadImage,
                  icon: const Icon(Icons.camera_alt, size: 24),
                  label: const Text(
                    '開啟相機或選取信封照片',
                    style: TextStyle(fontSize: 18),
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                const SizedBox(height: 20),

                // 3. 載入狀態 (轉圈圈)
                if (isLoading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: CircularProgressIndicator(),
                    ),
                  ),

                // 4. 錯誤訊息提示（包含 Excel 被佔用等狀況）
                if (errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Colors.red),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            errorMessage!,
                            style: const TextStyle(color: Colors.red, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 5. 辨識成功結果顯示
                if (scanResult != null) ...[
                  const SizedBox(height: 10),
                  Expanded(
                    child: Card(
                      elevation: 3,
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: ListView(
                          children: [
                            const Text(
                              '✅ 辨識與歸檔成功！',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.green,
                              ),
                            ),
                            const Divider(),
                            _buildResultRow('追蹤號碼', scanResult!['tracking_number']),
                            _buildResultRow('寄件人姓名', scanResult!['sender_name']),
                            _buildResultRow('寄件人地址', scanResult!['sender_address']),
                            _buildResultRow('收件人姓名', scanResult!['recipient_name']),
                            _buildResultRow('收件部門', scanResult!['recipient_department']),
                            _buildResultRow('收件人地址', scanResult!['recipient_address']),
                            _buildResultRow('歸檔日期', scanResult!['archive_date']),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value != null ? value.toString() : '無',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }
}