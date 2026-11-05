import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/date_symbol_data_local.dart'; // ✅ 1. 이 줄이 추가되었습니다!
import 'package:f2_telecom/firebase_options.dart';
import 'package:f2_telecom/screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ 2. 이 줄이 추가되었습니다! (날짜 표기법 초기화)
  await initializeDateFormatting();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F2텔레콤',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        useMaterial3: true,
      ),
      // 복사·붙여넣기·전체 선택 등 기본 메뉴와 날짜 선택창을 한글로
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // 휴대폰 아래 홈·뒤로가기 버튼(내비게이션 바) 자리를 피해서 모든 화면·목록창·대화상자를 그 위에 그림
      //  (안드로이드 15부터 앱이 화면 맨 아래까지 그려져서 아래쪽 버튼·목록이 가려지던 문제)
      builder: (context, child) => ColoredBox(
        color: Colors.white,
        child: SafeArea(top: false, left: false, right: false, child: child ?? const SizedBox()),
      ),
      home: const SplashScreen(),
    );
  }
}
