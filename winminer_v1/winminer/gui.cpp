#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <ObjIdl.h>
#include <gdiplus.h>
#pragma comment(lib, "gdiplus.lib")
#include <stdio.h>
#include <tchar.h>

LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
DWORD WINAPI start_gui(LPVOID lpParam);

static TCHAR szWindowClass[] = _T("MochimoGUI");
static TCHAR szTitle[] = _T("Mochimo Windows Miner");

HANDLE hGUIThread;
DWORD dwGUIThreadId;

Gdiplus::Image* ui_image;

int start_gui_thread() {
	hGUIThread = CreateThread(
		NULL,
		0,
		start_gui,
		NULL,
		0,
		&dwGUIThreadId
	);

	if (hGUIThread == NULL) {
		printf("Unable to start GUI Thread\n");
		return -1;
	}
}

int check_gui_thread_alive() {
	DWORD dwExitCode = WaitForSingleObject(hGUIThread, 0);
	if (dwExitCode == WAIT_TIMEOUT) {
		// Process is running;
		return 1;
	}
	else if (dwExitCode == WAIT_FAILED
		|| dwExitCode == WAIT_OBJECT_0
		|| dwExitCode == WAIT_ABANDONED) {
		printf("GUI no longer running\n");
		ExitProcess(1);
	}
	return 0;
}

DWORD WINAPI start_gui(LPVOID lpParam) {
	HINSTANCE hInstance = (HINSTANCE)GetModuleHandle(NULL);

	WNDCLASS wnd = {};
	wnd.lpfnWndProc = WndProc;
	wnd.hInstance = hInstance;
	wnd.lpszClassName = szWindowClass;
	RegisterClass(&wnd);


	HWND hWnd = CreateWindowEx(
		0,
		szWindowClass,
		szTitle,
		WS_OVERLAPPEDWINDOW,
		CW_USEDEFAULT, CW_USEDEFAULT,
		568, 548,
		NULL,
		NULL,
		hInstance,
		NULL
	);
	if (!hWnd) {
		printf("Unable to create main window\n");
		return -1;
	}

	HRGN hRegion = CreateRoundRectRgn(0, 0, 568, 548, 568, 548);
	//HRGN hRegion = CreateEllipticRgn(0, 0, 568, 548);
	SetWindowRgn(hWnd, hRegion, true);

	DWORD dwStyle = GetWindowLong(hWnd, GWL_STYLE);
	dwStyle &= ~(WS_CAPTION | WS_SIZEBOX | WS_MAXIMIZEBOX);
	SetWindowLong(hWnd, GWL_STYLE, dwStyle);

	SetWindowLong(hWnd, GWL_EXSTYLE, GetWindowLong(hWnd, GWL_EXSTYLE) | WS_EX_LAYERED);
	InvalidateRect(hWnd, NULL, TRUE);
	SetLayeredWindowAttributes(hWnd, 0, 255, LWA_ALPHA);

	Gdiplus::GdiplusStartupInput gdiplusStartupInput;
	ULONG_PTR gditoken;
	GdiplusStartup(&gditoken, &gdiplusStartupInput, NULL);

	ui_image = new Gdiplus::Image(L"mochiui.png");

	ShowWindow(hWnd, SW_SHOWDEFAULT);


	//Main message loop
	MSG msg;
	while (GetMessage(&msg, NULL, 0, 0)) {
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}

	delete ui_image;

	Gdiplus::GdiplusShutdown(gditoken);

	return 0;
}

void put_text(HDC hDc, int x, int y, char *str) {
	TextOutA(hDc, x, y, str, strlen(str));
}
LRESULT CALLBACK WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam) {
	switch (msg) {
	case WM_PAINT:
	{
		PAINTSTRUCT ps;
		HDC hDc = BeginPaint(hWnd, &ps);

		RECT r = ps.rcPaint;
		FillRect(hDc, &r, (HBRUSH)(COLOR_WINDOW + 1));
		
		Gdiplus::Rect gdi_rect(r.left, r.top, r.right-r.left, r.bottom-r.top);
		Gdiplus::Graphics ui_gfx(GetDC(hWnd));
		ui_gfx.DrawImage(ui_image, gdi_rect);

		SetBkMode(hDc, TRANSPARENT);
		SetTextColor(hDc, RGB(0, 80, 0));
		HFONT hFont = CreateFont(16, 0, 0, 0, FW_NORMAL, false, false, false, 0, 0, 0, 2, 0, "SYSTEM_FIXED_FONT");
		HFONT hTmp = (HFONT)SelectObject(hDc, hFont);
		put_text(hDc, 287, 35, "Mochimo");
		put_text(hDc, 285, 46, "Winminer v1.5");

		// Column 1
		put_text(hDc, 139, 140, "Haikurate");
		put_text(hDc, 183, 156, "MH/s");
		put_text(hDc, 139, 156, "123456");

		put_text(hDc, 139, 182, "Devices");
		put_text(hDc, 139, 198, "CUDA:");
		put_text(hDc, 198, 198, "99");
		put_text(hDc, 139, 214, "OpenCL:");
		put_text(hDc, 198, 214, "99");

		// Column 2
		put_text(hDc, 244, 140, "Block");
		put_text(hDc, 244, 156, "0x12345678");

		put_text(hDc, 244, 182, "Diff");
		put_text(hDc, 244, 198, "123");

		put_text(hDc, 244, 224, "TX Count");
		put_text(hDc, 244, 240, "12345678");

		put_text(hDc, 244, 266, "Solved");
		put_text(hDc, 244, 282, "12345678");


		DeleteObject(hFont);
		EndPaint(hWnd, &ps);

		return 0;
	}
	case WM_KEYDOWN:
		switch (wParam) {
		case VK_ESCAPE:
			PostQuitMessage(0);
			break;
		}
		return 0;
	case WM_LBUTTONDOWN:
		SendMessage(hWnd, WM_NCLBUTTONDOWN, HTCAPTION, NULL);
		break;
	case WM_DESTROY:
	{
		PostQuitMessage(0);
		return 0;
	}
	}

	return DefWindowProc(hWnd, msg, wParam, lParam);
}