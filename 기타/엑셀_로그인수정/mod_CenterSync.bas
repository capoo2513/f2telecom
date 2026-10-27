Attribute VB_Name = "mod_CenterSync"
Option Explicit

' ==========================================================================
' [통합국 시트] <-> Firebase(CenterData) 동기화        2026-10-26
'
'  통합국 시트 : 2행 제목, 3행부터 B 순번 / C 통합국명 / D 유형 / E 중심국명 / F 층·출입방법 정보
'  Firebase   : CenterData/<중심국명>  { name, tong, type, floor, floorBy, floorAt }
'
'  보내기(저장할 때)  : 지난번에 보낸 뒤 "바뀐 줄만" 올림 (숨김 시트 _동기화에 마지막으로 보낸 값 기억)
'                       F열이 비어 있으면 floor 는 건드리지 않음 → 앱에서 넣은 국사정보가 지워지지 않음
'  가져오기(열 때)    : 앱에서 입력/수정한 국사정보(floorBy = "app")만 받아서 F열에 채움
'                       내용이 바뀐 F칸은 빨간 글씨로 표시
'                       통합국 시트에 없는 중심국이면 맨 아래에 새 줄로 추가 (빨간 글씨)
'                       가져온 것은 floorBy = "excel" 로 바꿔둠 (같은 것을 다시 가져오지 않음)
'  지우기(저장할 때)  : 통합국 시트에서 지우거나 이름을 바꾼 중심국은 Firebase 에서도 지움
'                       (앱에서 새로 넣고 아직 엑셀로 안 가져온 것은 남김 → 다음에 열 때 가져옴)
'  수동 정리          : Alt+F8 → 통합국_Firebase정리 → 시트에 없는 중심국을 앱 추가분까지 모두 지움
'
'  ※ PROJECT_ID, SendToFirestore, HttpGetNoCache, CleanText 는 Module2,
'    SetAuthHeader 는 mod_FirebaseAuth 에 있는 것을 그대로 사용
' ==========================================================================

Private Const SHEET_NAME As String = "통합국"
Private Const SYNC_SHEET As String = "_동기화"
Private Const FIRST_ROW As Long = 3

' ------------------------------------------------------------
' [보내기] 바뀐 줄만 Firebase 로
' ------------------------------------------------------------
Public Sub SyncCenterData()
    Dim ws As Worksheet, lastRow As Long, r As Long
    Dim memo As Object, nm As String, sig As String
    Dim writes As String, cnt As Long, mask As String, fields As String

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)
    On Error GoTo 0
    If ws Is Nothing Then Exit Sub

    Set memo = LoadSyncMemo()
    lastRow = ws.Cells(ws.Rows.Count, "E").End(xlUp).Row

    For r = FIRST_ROW To lastRow
        nm = CleanText(ws.Cells(r, "E").Value)
        If nm <> "" Then
            sig = CleanText(ws.Cells(r, "C").Value) & "|" & CleanText(ws.Cells(r, "D").Value) & "|" & CleanText(ws.Cells(r, "F").Value)
            If memo("C|" & nm) <> sig Then
                fields = """name"":{""stringValue"":""" & nm & """}," & _
                         """tong"":{""stringValue"":""" & CleanText(ws.Cells(r, "C").Value) & """}," & _
                         """type"":{""stringValue"":""" & CleanText(ws.Cells(r, "D").Value) & """}"
                mask = """name"",""tong"",""type"""
                ' F열에 값이 있을 때만 국사정보를 올림 (빈칸으로 앱 값을 지우지 않음)
                If CleanText(ws.Cells(r, "F").Value) <> "" Then
                    fields = fields & ",""floor"":{""stringValue"":""" & CleanText(ws.Cells(r, "F").Value) & """}," & _
                             """floorBy"":{""stringValue"":""excel""}," & _
                             """floorAt"":{""timestampValue"":""" & UtcNow() & """}"
                    mask = mask & ",""floor"",""floorBy"",""floorAt"""
                End If
                If writes <> "" Then writes = writes & ","
                writes = writes & "{""update"":{""name"":""" & DocName(nm) & """,""fields"":{" & fields & "}}," & _
                                  """updateMask"":{""fieldPaths"":[" & mask & "]}}"
                memo("C|" & nm) = sig
                cnt = cnt + 1
                ' 한 번에 최대 500개까지 → 400개마다 끊어서 보냄
                If cnt Mod 400 = 0 Then
                    If Not CommitWrites(writes) Then Exit Sub
                    writes = ""
                End If
            End If
        End If
    Next r

    If writes <> "" Then
        If Not CommitWrites(writes) Then Exit Sub
    End If
    ' 시트에서 없어진 중심국: 기억장소에서 빼고 Firebase 에서도 지움
    Dim names As Object, k As Variant, removed As Boolean, delCnt As Long, delList As String
    Set names = SheetNames(ws)
    For Each k In memo.Keys
        If Left(k, 2) = "C|" Then
            If Not names.Exists(Mid(k, 3)) Then memo.Remove k: removed = True
        End If
    Next k
    If cnt > 0 Or removed Then SaveSyncMemo memo
    delCnt = DeleteMissingCenters(False, delList)
    Application.StatusBar = "통합국 " & cnt & "줄 보냄" & IIf(delCnt > 0, ", " & delCnt & "개 지움", "")
End Sub

' ------------------------------------------------------------
' [수동 정리] 통합국 시트에 없는 중심국을 Firebase 에서 모두 지움 (앱에서 넣은 것 포함)
'   Alt+F8 → 통합국_Firebase정리 실행
' ------------------------------------------------------------
Public Sub 통합국_Firebase정리()
    Dim n As Long, lst As String
    If MsgBox("통합국 시트(E열)에 없는 중심국을 앱(Firebase)에서 모두 지웁니다." & vbCrLf & _
              "앱에서 새로 입력하고 아직 엑셀로 가져오지 않은 중심국도 지워집니다." & vbCrLf & vbCrLf & "계속할까요?", _
              vbYesNo + vbExclamation, "통합국 정리") <> vbYes Then Exit Sub
    n = DeleteMissingCenters(True, lst)
    If n < 0 Then
        MsgBox "정리하지 못했습니다. (인터넷/로그인 확인, 또는 통합국 시트가 비어 있음)", vbExclamation, "통합국 정리"
    ElseIf n = 0 Then
        MsgBox "지울 중심국이 없습니다.", vbInformation, "통합국 정리"
    Else
        MsgBox n & "개를 지웠습니다." & vbCrLf & vbCrLf & lst, vbInformation, "통합국 정리"
    End If
End Sub

' 통합국 시트 E열 중심국명 목록
Private Function SheetNames(ws As Worksheet) As Object
    Dim d As Object, r As Long, lastRow As Long, nm As String
    Set d = CreateObject("Scripting.Dictionary")
    lastRow = ws.Cells(ws.Rows.Count, "E").End(xlUp).Row
    For r = FIRST_ROW To lastRow
        nm = CleanText(ws.Cells(r, "E").Value)
        If nm <> "" Then d(nm) = True
        nm = Trim(CStr(ws.Cells(r, "E").Value))
        If nm <> "" Then d(nm) = True
    Next r
    Set SheetNames = d
End Function

' Firebase 중심국 중 시트에 없는 것을 지움. 반환: 지운 개수 (-1 = 실패), lst = 지운 이름들
'   allApp = False : 앱에서 넣고 아직 엑셀로 안 가져온 것(floorBy = app)은 남김
Private Function DeleteMissingCenters(allApp As Boolean, ByRef lst As String) As Long
    Dim ws As Worksheet, names As Object, http As Object, url As String, body As String
    Dim res As Object, it As Variant, f As Object, nm As String, fb As String
    Dim writes As String, n As Long, part As Long

    DeleteMissingCenters = -1
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)
    On Error GoTo 0
    If ws Is Nothing Then Exit Function
    Set names = SheetNames(ws)
    If names.Count < 10 Then Exit Function   ' 시트가 비어 보이면 실수로 다 지우지 않게 중단

    url = "https://firestore.googleapis.com/v1/projects/" & PROJECT_ID & "/databases/(default)/documents:runQuery"
    body = "{""structuredQuery"":{""from"":[{""collectionId"":""CenterData""}]," & _
           """select"":{""fields"":[{""fieldPath"":""name""},{""fieldPath"":""floorBy""}]}}}"
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    On Error Resume Next
    http.Open "POST", url, False
    http.setRequestHeader "Content-Type", "application/json"
    SetAuthHeader http
    http.send body
    If Err.Number <> 0 Then Exit Function
    On Error GoTo 0
    If http.Status <> 200 Then Exit Function

    On Error Resume Next
    Set res = JsonConverter.ParseJson(http.responseText)
    On Error GoTo 0
    If res Is Nothing Then Exit Function

    lst = ""
    For Each it In res
        If it.Exists("document") Then
            nm = "": fb = ""
            If it("document").Exists("fields") Then
                Set f = it("document")("fields")
                If f.Exists("name") Then nm = Trim(f("name")("stringValue"))
                If f.Exists("floorBy") Then fb = f("floorBy")("stringValue")
            End If
            If nm <> "" And Not names.Exists(nm) And (allApp Or fb <> "app") Then
                If writes <> "" Then writes = writes & ","
                writes = writes & "{""delete"":""" & it("document")("name") & """}"
                lst = lst & nm & vbCrLf
                n = n + 1: part = part + 1
                If part = 400 Then
                    If Not CommitWrites(writes) Then Exit Function
                    writes = "": part = 0
                End If
            End If
        End If
    Next it
    If writes <> "" Then
        If Not CommitWrites(writes) Then Exit Function
    End If
    DeleteMissingCenters = n
End Function

' ------------------------------------------------------------
' [가져오기] 앱에서 넣은 국사정보만 F열로
' ------------------------------------------------------------
Public Sub 폰데이터가져오기_통합국()
    Dim ws As Worksheet, http As Object, url As String, body As String
    Dim res As Object, it As Variant, f As Object
    Dim nm As String, fl As String, r As Long, lastRow As Long, found As Boolean
    Dim got As Long, added As Long, acks As String

    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SHEET_NAME)
    On Error GoTo 0
    If ws Is Nothing Then Exit Sub

    url = "https://firestore.googleapis.com/v1/projects/" & PROJECT_ID & "/databases/(default)/documents:runQuery"
    body = "{""structuredQuery"":{""from"":[{""collectionId"":""CenterData""}]," & _
           """where"":{""fieldFilter"":{""field"":{""fieldPath"":""floorBy""},""op"":""EQUAL"",""value"":{""stringValue"":""app""}}}}}"

    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    On Error GoTo Fail
    http.Open "POST", url, False
    http.setRequestHeader "Content-Type", "application/json"
    SetAuthHeader http
    http.send body
    On Error GoTo 0
    If http.Status <> 200 Then
        MsgBox "통합국 국사정보를 가져오지 못했습니다. (" & http.Status & ")" & vbCrLf & Left(http.responseText, 200), vbExclamation
        Exit Sub
    End If

    On Error Resume Next
    Set res = JsonConverter.ParseJson(http.responseText)
    On Error GoTo 0
    If res Is Nothing Then Exit Sub

    lastRow = ws.Cells(ws.Rows.Count, "E").End(xlUp).Row
    For Each it In res
        If it.Exists("document") Then
            Set f = it("document")("fields")
            nm = "": fl = ""
            If f.Exists("name") Then nm = Trim(f("name")("stringValue"))
            If f.Exists("floor") Then fl = Trim(f("floor")("stringValue"))
            If nm <> "" And fl <> "" Then
                found = False
                For r = FIRST_ROW To lastRow
                    If Trim(ws.Cells(r, "E").Value) = nm Then
                        If CStr(ws.Cells(r, "F").Value) <> fl Then
                            ws.Cells(r, "F").Value = fl
                            ws.Cells(r, "F").Font.Color = vbRed   ' 앱에서 바뀐 칸은 빨간 글씨 (확인 후 직접 검정으로 바꾸세요)
                            got = got + 1
                        End If
                        found = True
                        Exit For
                    End If
                Next r
                If Not found Then
                    ' 통합국 시트에 없는 중심국 → 맨 아래 새 줄 (위 줄 서식 복사, 순번 +1)
                    lastRow = lastRow + 1
                    ws.Rows(lastRow - 1).Copy
                    ws.Rows(lastRow).PasteSpecial xlPasteFormats
                    Application.CutCopyMode = False
                    If IsNumeric(ws.Cells(lastRow - 1, "B").Value) Then ws.Cells(lastRow, "B").Value = ws.Cells(lastRow - 1, "B").Value + 1
                    ws.Cells(lastRow, "E").Value = nm
                    ws.Cells(lastRow, "F").Value = fl
                    ws.Range(ws.Cells(lastRow, "B"), ws.Cells(lastRow, "F")).Font.Color = vbRed   ' 새로 추가된 줄도 빨간 글씨
                    added = added + 1
                End If
                ' 가져온 것은 floorBy = excel 로 (다시 안 가져오고, 시트에서 지우면 저장할 때 Firebase 에서도 지워지도록)
                If acks <> "" Then acks = acks & ","
                acks = acks & "{""update"":{""name"":""" & it("document")("name") & """,""fields"":{""floorBy"":{""stringValue"":""excel""}}}," & _
                              """updateMask"":{""fieldPaths"":[""floorBy""]}}"
            End If
        End If
    Next it
    If acks <> "" Then CommitWrites acks
    Application.StatusBar = "통합국 국사정보 " & got & "건 반영, " & added & "건 새로 추가"
    Exit Sub
Fail:
    MsgBox "통합국 국사정보를 가져오는 중 서버에 연결하지 못했습니다.", vbExclamation
End Sub

' ------------------------------------------------------------
' 도구
' ------------------------------------------------------------
' 여러 문서를 한 번에 저장 (Firestore commit)
Private Function CommitWrites(writes As String) As Boolean
    Dim http As Object, url As String
    url = "https://firestore.googleapis.com/v1/projects/" & PROJECT_ID & "/databases/(default)/documents:commit"
    Set http = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    On Error Resume Next
    http.Open "POST", url, False
    http.setRequestHeader "Content-Type", "application/json"
    SetAuthHeader http
    http.send "{""writes"":[" & writes & "]}"
    If Err.Number <> 0 Or http.Status <> 200 Then
        MsgBox "통합국 업로드 실패 (" & http.Status & ")" & vbCrLf & Left(http.responseText, 200), vbExclamation, "업로드 실패"
        CommitWrites = False
    Else
        CommitWrites = True
    End If
    On Error GoTo 0
End Function

' 문서 경로 (중심국명이 문서 이름, / 는 _ 로)
Private Function DocName(nm As String) As String
    DocName = "projects/" & PROJECT_ID & "/databases/(default)/documents/CenterData/" & Replace(nm, "/", "_")
End Function

' 지금 시각 (UTC, 한국시간 -9시간)
Private Function UtcNow() As String
    UtcNow = Format(Now - TimeSerial(9, 0, 0), "yyyy-mm-dd\Thh:nn:ss") & "Z"
End Function

' 마지막으로 보낸 값 기억장소 (숨김 시트 _동기화 : A 키, B 값)
Private Function LoadSyncMemo() As Object
    Dim d As Object, ws As Worksheet, r As Long, lastRow As Long
    Set d = CreateObject("Scripting.Dictionary")
    Set ws = SyncSheet()
    lastRow = ws.Cells(ws.Rows.Count, "A").End(xlUp).Row
    For r = 1 To lastRow
        If ws.Cells(r, "A").Value <> "" Then d(CStr(ws.Cells(r, "A").Value)) = CStr(ws.Cells(r, "B").Value)
    Next r
    Set LoadSyncMemo = d
End Function

Private Sub SaveSyncMemo(d As Object)
    Dim ws As Worksheet, k As Variant, r As Long
    Set ws = SyncSheet()
    ws.Cells.ClearContents
    ws.Columns("A:B").NumberFormat = "@"
    r = 1
    For Each k In d.Keys
        ws.Cells(r, "A").Value = k
        ws.Cells(r, "B").Value = d(k)
        r = r + 1
    Next k
End Sub

Private Function SyncSheet() As Worksheet
    Dim ws As Worksheet
    On Error Resume Next
    Set ws = ThisWorkbook.Sheets(SYNC_SHEET)
    On Error GoTo 0
    If ws Is Nothing Then
        Set ws = ThisWorkbook.Sheets.Add(After:=ThisWorkbook.Sheets(ThisWorkbook.Sheets.Count))
        ws.Name = SYNC_SHEET
        ws.Visible = xlSheetVeryHidden
    End If
    Set SyncSheet = ws
End Function
