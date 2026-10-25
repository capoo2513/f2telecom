Attribute VB_Name = "mod_FirebaseAuth"
Option Explicit
' ==========================================================
' [엑셀 -> 파이어베이스 로그인]  (f2-telecom-online)
'  파이어베이스 보안 규칙을 "로그인한 사람만"으로 강화해도
'  엑셀 동기화가 계속 되도록, 엑셀 전용 사용자로 로그인해서
'  받은 출입증(토큰)을 요청마다 붙입니다.
'  ※ 이 모듈에 비밀번호가 있으므로 VBA 프로젝트에 암호를 꼭 걸어주세요.
' ==========================================================
Private Const FB_API_KEY As String = "AIzaSyD5VL2dQF615MS6fAvKYTvMKk83JAr7nNM"   ' 웹 API 키 (공개되어도 되는 값)
Private Const SYNC_EMAIL As String = "excel-sync@f2telecom.com"
Private Const SYNC_PASSWORD As String = "여기에_비밀번호"     ' ★ 직접 입력하세요

Private mToken As String
Private mTokenTime As Date

' 로그인 토큰 받기 (50분 동안은 다시 로그인하지 않고 재사용)
Public Function GetIdToken() As String
    If mToken <> "" And (Now - mTokenTime) < TimeSerial(0, 50, 0) Then
        GetIdToken = mToken
        Exit Function
    End If

    Dim http As Object, body As String, res As Object
    Set http = CreateObject("MSXML2.XMLHTTP")
    body = "{""email"":""" & SYNC_EMAIL & """,""password"":""" & SYNC_PASSWORD & """,""returnSecureToken"":true}"

    On Error GoTo Fail
    http.Open "POST", "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=" & FB_API_KEY, False
    http.setRequestHeader "Content-Type", "application/json"
    http.send body

    If http.Status <> 200 Then GoTo Fail
    Set res = JsonConverter.ParseJson(http.responseText)
    mToken = res("idToken")
    mTokenTime = Now
    GetIdToken = mToken
    Exit Function

Fail:
    mToken = ""
    GetIdToken = ""
    Dim detail As String
    On Error Resume Next
    detail = http.Status & " " & Left(http.responseText, 300)
    On Error GoTo 0
    MsgBox "파이어베이스 로그인에 실패했습니다." & vbCrLf & _
           "(엑셀 전용 사용자 이메일/비밀번호를 확인하세요)" & vbCrLf & vbCrLf & detail, _
           vbCritical, "동기화 로그인 실패"
End Function

' http.Open 다음 줄에서 호출 → 로그인 토큰을 붙임
Public Sub SetAuthHeader(http As Object)
    Dim t As String
    t = GetIdToken()
    If t <> "" Then http.setRequestHeader "Authorization", "Bearer " & t
End Sub
