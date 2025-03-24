import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const MyApp());
}

class AppSettings {
  ThemeMode themeMode;
  int focusTimeMinutes;
  int breakTimeMinutes;

  AppSettings({
    this.themeMode = ThemeMode.dark,
    this.focusTimeMinutes = 50,
    this.breakTimeMinutes = 10,
  });

  Future<void> saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', themeMode.index);
    await prefs.setInt('focusTimeMinutes', focusTimeMinutes);
    await prefs.setInt('breakTimeMinutes', breakTimeMinutes);
  }

  static Future<AppSettings> loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return AppSettings(
      themeMode: ThemeMode.values[prefs.getInt('themeMode') ?? 0],
      focusTimeMinutes: prefs.getInt('focusTimeMinutes') ?? 50,
      breakTimeMinutes: prefs.getInt('breakTimeMinutes') ?? 10,
    );
  }
}

// 집중 시간 기록을 위한 모델 클래스
class FocusRecord {
  final DateTime date;
  final int focusMinutes;

  FocusRecord({
    required this.date,
    required this.focusMinutes,
  });

  // 날짜별 집계를 위한 날짜만 가져오는 함수
  String get dateString => DateFormat('yyyy-MM-dd').format(date);

  // JSON 변환을 위한 메서드
  Map<String, dynamic> toJson() => {
    'date': date.millisecondsSinceEpoch,
    'focusMinutes': focusMinutes,
  };

  // JSON에서 객체 생성을 위한 팩토리 메서드
  factory FocusRecord.fromJson(Map<String, dynamic> json) {
    return FocusRecord(
      date: DateTime.fromMillisecondsSinceEpoch(json['date']),
      focusMinutes: json['focusMinutes'],
    );
  }
}

// 집중 시간 기록을 관리하는 클래스
class FocusHistoryManager {
  static const _storageKey = 'focus_history';
  List<FocusRecord> _records = [];

  // 저장된 기록 불러오기
  Future<void> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = prefs.getStringList(_storageKey) ?? [];
    _records = recordsJson
        .map((json) => FocusRecord.fromJson(jsonDecode(json)))
        .toList();
  }

  // 기록 저장하기
  Future<void> saveRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final recordsJson = _records
        .map((record) => jsonEncode(record.toJson()))
        .toList();
    await prefs.setStringList(_storageKey, recordsJson);
  }

  // 새 기록 추가
  Future<void> addRecord(FocusRecord record) async {
    _records.add(record);
    await saveRecords();
  }

  // 날짜별 집중 시간 합계 가져오기
  int getFocusMinutesForDate(DateTime date) {
    final dateString = DateFormat('yyyy-MM-dd').format(date);
    return _records
        .where((record) => record.dateString == dateString)
        .fold(0, (sum, record) => sum + record.focusMinutes);
  }

  // 날짜별 이벤트 맵 생성 (캘린더 표시용)
  Map<DateTime, List<FocusRecord>> getEventsMap() {
    final eventsMap = <DateTime, List<FocusRecord>>{};
    
    for (final record in _records) {
      final date = DateTime(
        record.date.year,
        record.date.month,
        record.date.day,
      );
      
      if (eventsMap[date] == null) {
        eventsMap[date] = [];
      }
      
      eventsMap[date]!.add(record);
    }
    
    return eventsMap;
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  AppSettings settings = AppSettings();
  final FocusHistoryManager historyManager = FocusHistoryManager();
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    settings = await AppSettings.loadFromPrefs();
    await historyManager.loadRecords();
    setState(() {
      isLoading = false;
    });
  }

  void updateSettings(AppSettings newSettings) {
    setState(() {
      settings = newSettings;
    });
    settings.saveToPrefs();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }
    
    return MaterialApp(
      title: '공부 타이머',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: Colors.black,
      ),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: ClockScreen(
        settings: settings,
        historyManager: historyManager,
        onSettingsChanged: updateSettings,
      ),
    );
  }
}

class ClockScreen extends StatefulWidget {
  final AppSettings settings;
  final FocusHistoryManager historyManager;
  final Function(AppSettings) onSettingsChanged;

  const ClockScreen({
    super.key,
    required this.settings,
    required this.historyManager,
    required this.onSettingsChanged,
  });

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
  int _elapsedFocusSeconds = 0;
  DateTime? _lastFocusStartTime;

  @override
  void initState() {
    super.initState();
    resetTimer();
    
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now();
        if (_isTimerActive) {
          _remainingSeconds--;
          if (!_isBreakTime) {
            _elapsedFocusSeconds++;
          }
          
          if (_remainingSeconds <= 0) {
            if (_isBreakTime) {
              // 휴식 시간이 끝나면 다시 공부 타이머로 변경
              _isBreakTime = false;
              _totalSeconds = widget.settings.focusTimeMinutes * 60;
              _remainingSeconds = _totalSeconds;
              _lastFocusStartTime = DateTime.now();
            } else {
              // 집중 시간 종료 시 기록 저장
              _saveFocusRecord();
              
              // 공부 시간이 끝나면 휴식 타이머로 변경
              _isBreakTime = true;
              _totalSeconds = widget.settings.breakTimeMinutes * 60;
              _remainingSeconds = _totalSeconds;
            }
          }
        }
      });
    });
  }

  void _saveFocusRecord() {
    if (_elapsedFocusSeconds > 0) {
      final focusMinutes = _elapsedFocusSeconds ~/ 60;
      if (focusMinutes > 0) {
        final record = FocusRecord(
          date: _lastFocusStartTime ?? DateTime.now(),
          focusMinutes: focusMinutes,
        );
        widget.historyManager.addRecord(record);
        _elapsedFocusSeconds = 0;
      }
    }
  }

  @override
  void didUpdateWidget(ClockScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.focusTimeMinutes != widget.settings.focusTimeMinutes ||
        oldWidget.settings.breakTimeMinutes != widget.settings.breakTimeMinutes) {
      // 설정이 변경되었을 때 타이머가 활성 상태가 아니라면 초기값 갱신
      if (!_isTimerActive) {
        resetTimer();
      }
    }
  }

  @override
  void dispose() {
    // 앱 종료시 현재까지의 집중 시간 기록 저장
    if (_isTimerActive && !_isBreakTime) {
      _saveFocusRecord();
    }
    _timer.cancel();
    super.dispose();
  }

  void _toggleTimer() {
    setState(() {
      if (!_isTimerActive) {
        // 타이머 시작
        _isTimerActive = true;
        if (!_isBreakTime) {
          _lastFocusStartTime = DateTime.now();
        }
      } else {
        // 타이머 일시 정지
        _isTimerActive = false;
        // 집중 시간 중 일시 정지 시 기록 저장
        if (!_isBreakTime) {
          _saveFocusRecord();
        }
      }
    });
  }

  void resetTimer() {
    // 타이머 재설정 시 현재까지의 집중 시간 기록 저장
    if (_isTimerActive && !_isBreakTime) {
      _saveFocusRecord();
    }
    
    setState(() {
      _isTimerActive = false;
      _isBreakTime = false;
      _totalSeconds = widget.settings.focusTimeMinutes * 60;
      _remainingSeconds = _totalSeconds;
      _elapsedFocusSeconds = 0;
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

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SettingsScreen(
          settings: widget.settings,
          onSettingsChanged: widget.onSettingsChanged,
        ),
      ),
    );
  }

  void _openCalendar() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CalendarScreen(
          historyManager: widget.historyManager,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final backgroundColor = isDarkMode ? Colors.black : Colors.white;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Stack(
          children: [
            // 설정 & 캘린더 버튼
            Positioned(
              top: 20,
              left: 20,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings),
                    color: textColor,
                    onPressed: _openSettings,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.calendar_month),
                    color: textColor,
                    onPressed: _openCalendar,
                  ),
                ],
              ),
            ),
            
            // 시계 - 크기 증가
            Center(
              child: Text(
                _formatTime(_currentTime),
                style: TextStyle(
                  color: textColor,
                  fontSize: 150, // 크기 증가
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            
            // 타이머 표시
            if (_isTimerActive || _remainingSeconds < _totalSeconds)
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
                        style: TextStyle(
                          color: textColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      progressColor: _isBreakTime ? Colors.green : Colors.blue,
                      backgroundColor: Colors.grey.shade800,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isBreakTime ? '휴식 시간' : '집중 시간',
                      style: TextStyle(
                        color: _isBreakTime ? Colors.green : Colors.blue,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            
            // 타이머 제어 버튼들
            Positioned(
              bottom: 20,
              right: 20,
              child: Row(
                children: [
                  // 초기화 버튼
                  FloatingActionButton(
                    onPressed: resetTimer,
                    backgroundColor: Colors.orange,
                    heroTag: 'reset',
                    child: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 16),
                  // 시작/일시정지 버튼
                  FloatingActionButton(
                    onPressed: _toggleTimer,
                    backgroundColor: _isTimerActive ? Colors.red : Colors.blue,
                    heroTag: 'toggle',
                    child: Icon(
                      _isTimerActive ? Icons.pause : Icons.play_arrow,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 캘린더 화면
class CalendarScreen extends StatefulWidget {
  final FocusHistoryManager historyManager;

  const CalendarScreen({
    super.key,
    required this.historyManager,
  });

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  CalendarFormat _calendarFormat = CalendarFormat.month;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _selectedDay = _focusedDay;
  }

  // 시간을 시간:분 형식으로 변환
  String _formatFocusTime(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours > 0 ? '${hours}시간 ' : ''}${mins}분';
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    final focusTimeColor = isDarkMode ? Colors.orange : Colors.blue;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('집중 시간 기록', style: TextStyle(color: textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Column(
            children: [
              TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2030, 12, 31),
                focusedDay: _focusedDay,
                calendarFormat: _calendarFormat,
                availableCalendarFormats: const {
                  CalendarFormat.month: '월',
                  CalendarFormat.week: '주',
                },
                headerStyle: HeaderStyle(
                  formatButtonTextStyle: TextStyle(color: textColor),
                  titleTextStyle: TextStyle(color: textColor),
                  leftChevronIcon: Icon(Icons.chevron_left, color: textColor),
                  rightChevronIcon: Icon(Icons.chevron_right, color: textColor),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: textColor),
                  weekendStyle: TextStyle(color: Colors.red[300]),
                ),
                selectedDayPredicate: (day) {
                  return isSameDay(_selectedDay, day);
                },
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onFormatChanged: (format) {
                  setState(() {
                    _calendarFormat = format;
                  });
                },
                onPageChanged: (focusedDay) {
                  _focusedDay = focusedDay;
                },
                calendarStyle: CalendarStyle(
                  markersMaxCount: 1,
                  outsideDaysVisible: false,
                  // 오늘 날짜를 테두리로만 표시
                  todayDecoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDarkMode ? Colors.white : Colors.black,
                      width: 1.5,
                    ),
                    color: Colors.transparent,
                  ),
                  // 오늘 날짜의 텍스트 색상
                  todayTextStyle: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                  // 선택된 날짜 스타일
                  selectedDecoration: BoxDecoration(
                    color: const Color.fromARGB(255, 115, 104, 136),
                    shape: BoxShape.circle,
                  ),
                  // 일반 날짜 텍스트 스타일
                  defaultTextStyle: TextStyle(color: textColor),
                  weekendTextStyle: TextStyle(color: Colors.red[300]),
                ),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (context, date, events) {
                    final focusMinutes = widget.historyManager.getFocusMinutesForDate(date);
                    if (focusMinutes > 0) {
                      return Container(
                        margin: const EdgeInsets.only(top: 30), // 마커 위치 조정
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(
                          color: focusTimeColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatFocusTime(focusMinutes),
                          style: TextStyle(
                            color: isDarkMode ? Colors.orange : Colors.blue,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      );
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final Function(AppSettings) onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _currentSettings;
  late TextEditingController _focusTimeController;
  late TextEditingController _breakTimeController;

  @override
  void initState() {
    super.initState();
    _currentSettings = AppSettings(
      themeMode: widget.settings.themeMode,
      focusTimeMinutes: widget.settings.focusTimeMinutes,
      breakTimeMinutes: widget.settings.breakTimeMinutes,
    );
    _focusTimeController = TextEditingController(
      text: _currentSettings.focusTimeMinutes.toString(),
    );
    _breakTimeController = TextEditingController(
      text: _currentSettings.breakTimeMinutes.toString(),
    );
  }

  @override
  void dispose() {
    _focusTimeController.dispose();
    _breakTimeController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    // 입력값 검증
    final focusTime = int.tryParse(_focusTimeController.text) ?? 50;
    final breakTime = int.tryParse(_breakTimeController.text) ?? 10;
    
    _currentSettings.focusTimeMinutes = focusTime.clamp(1, 120);
    _currentSettings.breakTimeMinutes = breakTime.clamp(1, 60);
    
    widget.onSettingsChanged(_currentSettings);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('설정', style: TextStyle(color: textColor)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('테마 설정', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            
            // 테마 모드 선택
            RadioListTile<ThemeMode>(
              title: const Text('라이트 모드'),
              value: ThemeMode.light,
              groupValue: _currentSettings.themeMode,
              onChanged: (value) {
                setState(() {
                  _currentSettings.themeMode = value!;
                });
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('다크 모드'),
              value: ThemeMode.dark,
              groupValue: _currentSettings.themeMode,
              onChanged: (value) {
                setState(() {
                  _currentSettings.themeMode = value!;
                });
              },
            ),
            RadioListTile<ThemeMode>(
              title: const Text('시스템 설정'),
              value: ThemeMode.system,
              groupValue: _currentSettings.themeMode,
              onChanged: (value) {
                setState(() {
                  _currentSettings.themeMode = value!;
                });
              },
            ),
            
            const Divider(),
            const SizedBox(height: 16),
            
            // 타이머 설정
            Text('타이머 설정', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _focusTimeController,
                    decoration: const InputDecoration(
                      labelText: '집중 시간 (분)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _breakTimeController,
                    decoration: const InputDecoration(
                      labelText: '휴식 시간 (분)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // 저장 버튼
            Center(
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                ),
                child: const Text('저장', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

