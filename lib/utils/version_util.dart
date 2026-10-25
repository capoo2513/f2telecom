/// 앱 버전 비교 도구
///
/// "1.1.10" 처럼 점(.)으로 나눈 숫자를 앞에서부터 비교합니다.
/// (문자로 비교하면 "1.1.10" 이 "1.1.9" 보다 작게 나오는 문제가 있어 숫자로 비교)
///
/// 서버 버전(server)이 내 앱 버전(current)보다 높을 때만 true
/// - 같은 버전이거나, 시험용으로 더 새 버전을 먼저 깔았을 때는 false (업데이트 창 안 뜸)
bool isNewerVersion(String server, String current) {
  List<int> parse(String v) => v
      .trim()
      .split('+')
      .first
      .split('.')
      .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
      .toList();

  final a = parse(server);
  final b = parse(current);
  final n = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
