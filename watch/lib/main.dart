import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:percent_indicator/circular_percent_indicator.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '공부 타이머',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
      ),
      home: const ClockScreen(),
    );
  }
}

class ClockScreen extends StatefulWidget {
  const ClockScreen({super.key});

  @override
  State<ClockScreen> createState() => _ClockScreenState();
}

class _ClockScreenState extends State<ClockScreen> {
  late Timer _timer;
  DateTime _currentTime = DateTime.now();
  bool _isTimerActive = false;
  bool _isBreakTime = false;
  int _remainingSeconds = 0;
  int _totalSeconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now();
        if (_isTimerActive) {
          _remainingSeconds--;
          if (_remainingSeconds <= 0) {
            if (_isBreakTime) {
              // 휴식 시간이 끝나면 다시 공부 타이머로 변경
              _isBreakTime = false;
              _totalSeconds = 50 * 60; // 50분
              _remainingSeconds = _totalSeconds;
            } else {
              // 공부 시간이 끝나면 휴식 타이머로 변경
              _isBreakTime = true;
              _totalSeconds = 10 * 60; // 10분
              _remainingSeconds = _totalSeconds;
            }
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    setState(() {
      if (!_isTimerActive) {
        _isTimerActive = true;
        _isBreakTime = false;
        _totalSeconds = 50 * 60; // 50분
        _remainingSeconds = _totalSeconds;
      } else {
        _isTimerActive = false;
      }
    });
  }

  String _formatTime(DateTime time) {
    return DateFormat('HH:mm:ss').format(time);
  }

  String _formatRemainingTime() {
    int minutes = _remainingSeconds ~/ 60;
    int seconds = _remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Text(
                _formatTime(_currentTime),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 120,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (_isTimerActive)
              Positioned(
                top: 20,
                right: 20,
                child: Column(
                  children: [
                    CircularPercentIndicator(
                      radius: 60.0,
                      lineWidth: 10.0,
                      percent: _remainingSeconds / _totalSeconds,
                      center: Text(
                        _formatRemainingTime(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      progressColor: _isBreakTime ? Colors.green : Colors.blue,
                      backgroundColor: Colors.grey.shade800,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isBreakTime ? '휴식 시간' : '공부 시간',
                      style: TextStyle(
                        color: _isBreakTime ? Colors.green : Colors.blue,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              bottom: 20,
              right: 20,
              child: FloatingActionButton(
                onPressed: _toggleTimer,
                backgroundColor: _isTimerActive ? Colors.red : Colors.blue,
                child: Icon(
                  _isTimerActive ? Icons.pause : Icons.timer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
