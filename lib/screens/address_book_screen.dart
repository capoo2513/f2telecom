import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'address_detail_screen.dart';
import '../utils/suggestion_helper.dart'; // (없으면 주석 처리)

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  // 데이터 관련
  List<List<dynamic>> _allData = [];
  List<List<dynamic>> _foundData = [];
  bool _isLoading = true;

  // 즐겨찾기 & 검색 기록
  List<String> _favoriteStations = [];
  List<String> _recentSearches = [];
  bool _showFavoritesOnly = false;
  bool _showRecentHistory = false;

  // 컨트롤러
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // ★ [수정] 점수 기반 권한 변수
  int _myScore = 0; // 0:잠금, 1:제한, 2:전체, 3:관리
  bool _isAdmin = false; // 3점일 때 true (관리자 기능)
  bool _isFabExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadCSV();
    _loadFavorites();
    _loadRecentSearches();
    _checkUserScore(); // 레벨 대신 점수 확인

    _searchFocus.addListener(() {
      setState(() {
        _showRecentHistory =
            _searchFocus.hasFocus && _searchController.text.isEmpty;
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // ★ [핵심 변경] DB에서 'address' 점수 가져오기
  Future<void> _checkUserScore() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        if (mounted) {
          setState(() {
            // access_scores 맵에서 'address' 점수를 가져옴 (없으면 0점)
            Map<String, dynamic> scores = doc.data()!['access_scores'] ?? {};
            _myScore = scores['address'] ?? 0;

            // 3점 이상일 때 관리자(삭제 등) 권한 부여
            _isAdmin = _myScore >= 3;
          });
        }
      }
    }
  }

  // CSV 로드
  void _loadCSV() async {
    try {
      String csvString = "";
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/addresses.csv');

      if (await file.exists()) {
        csvString = await file.readAsString();
      } else {
        csvString = await rootBundle.loadString("assets/addresses.csv");
      }

      List<List<dynamic>> listData =
          const CsvToListConverter().convert(csvString);
      if (listData.isNotEmpty) listData.removeAt(0);

      if (mounted) {
        setState(() {
          _allData = listData;
          _foundData = listData;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 즐겨찾기 로드/저장/토글
  void _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _favoriteStations = prefs.getStringList('favorites') ?? [];
    });
  }

  void _toggleFavorite(String name) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      if (_favoriteStations.contains(name)) {
        _favoriteStations.remove(name);
      } else {
        _favoriteStations.add(name);
      }
    });
    await prefs.setStringList('favorites', _favoriteStations);
    if (_showFavoritesOnly) _runFilter(_searchController.text);
  }

  // 최근 검색어 로드/저장/삭제
  void _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches = prefs.getStringList('recent_searches') ?? [];
    });
  }

  void _addRecentSearch(String keyword) async {
    if (keyword.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches.remove(keyword);
      _recentSearches.insert(0, keyword);
      if (_recentSearches.length > 10) _recentSearches.removeLast();
    });
    await prefs.setStringList('recent_searches', _recentSearches);
  }

  void _removeRecentSearch(String keyword) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _recentSearches.remove(keyword);
    });
    await prefs.setStringList('recent_searches', _recentSearches);
  }

  // 검색 필터 실행
  void _runFilter(String keyword) {
    List<List<dynamic>> results = [];
    if (keyword.isEmpty) {
      results = _allData;
      if (_searchFocus.hasFocus) setState(() => _showRecentHistory = true);
    } else {
      setState(() => _showRecentHistory = false);
      results = _allData
          .where((row) =>
              row[0].toString().contains(keyword) ||
              row[1].toString().contains(keyword))
          .toList();
    }

    if (_showFavoritesOnly) {
      results = results
          .where((row) => _favoriteStations.contains(row[0].toString()))
          .toList();
    }

    setState(() => _foundData = results);
  }

  // 건의사항 다이얼로그
  void _showSuggestionDialog() async {
    final controller = TextEditingController();
    String userName = "익명";
    String userEmail = "익명";

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      userEmail = user.email ?? "-";
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (userDoc.exists) {
        userName = userDoc.data()?['name'] ?? "이름없음";
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("건의사항 보내기"),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
              hintText: "내용을 입력해주세요.", border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text("취소")),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isNotEmpty) {
                await FirebaseFirestore.instance.collection('suggestions').add({
                  'content': controller.text,
                  'writerEmail': userEmail,
                  'writerName': userName,
                  'createdAt': FieldValue.serverTimestamp(),
                });

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text("전송 완료")));
                  setState(() => _isFabExpanded = false);
                }
              }
            },
            child: const Text("전송"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('주소록'),
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white),
      floatingActionButton: _isAdmin
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_isFabExpanded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: FloatingActionButton.extended(
                      onPressed: _showSuggestionDialog,
                      label: const Text("건의사항 보내기"),
                      icon: const Icon(Icons.edit),
                      backgroundColor: Colors.orange,
                    ),
                  ),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: Colors.indigo,
                  child: Icon(_isFabExpanded ? Icons.close : Icons.feedback),
                  onPressed: () =>
                      setState(() => _isFabExpanded = !_isFabExpanded),
                ),
              ],
            ),
      body: Column(
        children: [
          // 1. 검색창 영역
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onChanged: _runFilter,
                    onSubmitted: (value) {
                      _addRecentSearch(value);
                      _runFilter(value);
                    },
                    decoration: InputDecoration(
                      labelText: '국소명 또는 주소 검색',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _searchController.clear();
                                _runFilter('');
                                _searchFocus.requestFocus();
                              },
                            )
                          : null,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 0, horizontal: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    setState(() {
                      _showFavoritesOnly = !_showFavoritesOnly;
                      _runFilter(_searchController.text);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _showFavoritesOnly
                          ? Colors.amber[100]
                          : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _showFavoritesOnly
                              ? Colors.amber
                              : Colors.transparent),
                    ),
                    child: Icon(
                      _showFavoritesOnly ? Icons.star : Icons.star_border,
                      color:
                          _showFavoritesOnly ? Colors.amber[800] : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 2. 메인 컨텐츠
          Expanded(
            child: Stack(
              children: [
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _foundData.isEmpty
                        ? Center(
                            child: Text(_showFavoritesOnly
                                ? "즐겨찾기 항목이 없습니다."
                                : "검색 결과가 없습니다."))
                        : ListView.builder(
                            itemCount: _foundData.length,
                            itemBuilder: (context, index) {
                              final row = _foundData[index];
                              String name =
                                  row.length > 0 ? row[0].toString() : "";
                              String addr =
                                  row.length > 1 ? row[1].toString() : "";
                              String type =
                                  row.length > 2 ? row[2].toString() : "";
                              String cat =
                                  row.length > 3 ? row[3].toString() : "";
                              String tmap =
                                  row.length > 4 ? row[4].toString() : "";
                              String note =
                                  row.length > 5 ? row[5].toString() : "";
                              bool isFav = _favoriteStations.contains(name);

                              return ListTile(
                                leading: const Icon(Icons.location_on,
                                    color: Colors.indigo),
                                title: Text(name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(addr),
                                trailing: IconButton(
                                  icon: Icon(
                                      isFav ? Icons.star : Icons.star_border,
                                      color:
                                          isFav ? Colors.amber : Colors.grey),
                                  onPressed: () => _toggleFavorite(name),
                                ),
                                onTap: () {
                                  _addRecentSearch(name);
                                  // ★ [핵심] 상세 화면으로 '내 점수(_myScore)' 전달
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => AddressDetailScreen(
                                        title: name,
                                        address: addr,
                                        type: type,
                                        category: cat,
                                        tmapAddress: tmap,
                                        specialNote: note,
                                        // ★ 이 부분이 중요! 점수를 넘겨줌
                                        userScore: _myScore,
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),

                // 최근 검색어 패널
                if (_showRecentHistory)
                  Container(
                    color: Colors.white.withOpacity(0.95),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          color: Colors.grey[200],
                          child: const Text("🕒 최근 검색어",
                              style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        Expanded(
                          child: _recentSearches.isEmpty
                              ? const Center(child: Text("최근 검색 기록이 없습니다."))
                              : ListView.builder(
                                  itemCount: _recentSearches.length,
                                  itemBuilder: (context, index) {
                                    final keyword = _recentSearches[index];
                                    return ListTile(
                                      leading:
                                          const Icon(Icons.history, size: 18),
                                      title: Text(keyword),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        onPressed: () =>
                                            _removeRecentSearch(keyword),
                                      ),
                                      onTap: () {
                                        _searchController.text = keyword;
                                        _searchFocus.unfocus();
                                        _runFilter(keyword);
                                        _addRecentSearch(keyword);
                                      },
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
