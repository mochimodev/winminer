#define WIN32_LEAN_AND_MEAN
#include <Windows.h>
#include <ObjIdl.h>
#include <gdiplus.h>
#pragma comment(lib, "gdiplus.lib")
#include <stdio.h>
#include <tchar.h>

#include "winminer.h"
#include "miner.h"

#include "resource.h"

#include "gui.h"

LRESULT CALLBACK WndProc(HWND, UINT, WPARAM, LPARAM);
VOID CALLBACK RedrawTimerProc(HWND hWnd, UINT msg, UINT timerId, DWORD dwTime);
DWORD WINAPI start_gui(LPVOID lpParam);

static TCHAR szWindowClass[] = _T("MochimoGUI");
static TCHAR szTitle[] = _T("Mochimo Windows Miner");

HANDLE hGUIThread;
DWORD dwGUIThreadId;
HBITMAP ui_bitmap;
HDC ui_hDc;

char status_str[64];

Gdiplus::Image* ui_image;
static const uint32_t width = 568, height = 548;

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
	return 0;
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
		return 0;
	}
	return 0;
}

DWORD WINAPI start_gui(LPVOID lpParam) {
	HINSTANCE hInstance = (HINSTANCE)GetModuleHandle(NULL);

	set_status("initializing");

	WNDCLASS wnd = {};
	wnd.lpfnWndProc = WndProc;
	wnd.hInstance = hInstance;
	wnd.lpszClassName = szWindowClass;
	wnd.hbrBackground = NULL;
	wnd.hCursor = LoadCursor(NULL, IDC_ARROW);
	RegisterClass(&wnd);

	HWND hWnd = CreateWindowEx(
		0,
		szWindowClass,
		szTitle,
		WS_OVERLAPPEDWINDOW,
		CW_USEDEFAULT, CW_USEDEFAULT,
		width, height,
		NULL,
		NULL,
		hInstance,
		NULL
	);
	if (!hWnd) {
		printf("Unable to create main window\n");
		return -1;
	}

	HRGN hRegion = CreateRoundRectRgn(0, 0, width, height, width, height);
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

	// Predraw the UI to a bitmap
	HRSRC rsc = FindResource(NULL, MAKEINTRESOURCE(IDB_BGPNG), _T("PNG"));
	if (rsc == NULL) {
		DWORD dwErr = GetLastError();
		printf("FindResource failed. Error: %lu\n", dwErr);
		return 0;
	}
	HGLOBAL resGlobal = LoadResource(NULL, rsc);
	void *img = LockResource(resGlobal);
	DWORD dwSize = SizeofResource(NULL, rsc);
	if (!dwSize) {
		printf("Failed to get size of BGPNG\n");
		return 0;
	}
	HGLOBAL resGlobal2 = GlobalAlloc(GMEM_MOVEABLE, dwSize);
	if (!resGlobal2) {
		printf("Failed to allocate resGlobal2\n");
		return 0;
	}
	void *buf = GlobalLock(resGlobal2);
	if (!buf) {
		printf("GlobalLock failed\n");
		return 0;
	}
	CopyMemory(buf, img, dwSize);
	IStream *imgStream = NULL;
	HRESULT hRes = CreateStreamOnHGlobal(resGlobal2, TRUE, &imgStream);
	if (hRes != S_OK) {
		printf("CreateStreamOnHGlobal failed\n");
		return 0;
	}
	ui_image = Gdiplus::Image::FromStream(imgStream);
	imgStream->Release();
	Gdiplus::Rect gdi_rect(0, 0, width, height);
	HDC hDc = GetDC(hWnd);
	ui_hDc = CreateCompatibleDC(hDc);
	ui_bitmap = CreateCompatibleBitmap(hDc, width, height);
	SelectObject(ui_hDc, ui_bitmap);
	Gdiplus::Graphics ui_gfx(ui_hDc);
	ui_gfx.DrawImage(ui_image, gdi_rect);

	// Draw a translucent black layer on top to make it look more like a watermark
	Gdiplus::SolidBrush brush(Gdiplus::Color(215, 0, 0, 0));
	ui_gfx.FillRectangle(&brush, 0, 0, width, height);
	

	ShowWindow(hWnd, SW_SHOWDEFAULT);

	// Start 1s timer, to have a WM_TIMER event to trigger redraw in.
	UINT_PTR timerId = SetTimer(hWnd, NULL, 1000, (TIMERPROC)RedrawTimerProc);

	//Main message loop
	MSG msg;
	while (GetMessage(&msg, NULL, 0, 0)) {
		TranslateMessage(&msg);
		DispatchMessage(&msg);
	}

	delete ui_image;
	DeleteObject(ui_bitmap);
	DeleteDC(ui_hDc);

	//Gdiplus::GdiplusShutdown(gditoken);

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
		
		BitBlt(hDc, 0, 0, width, height, ui_hDc, 0, 0, SRCCOPY);

		SetBkMode(hDc, TRANSPARENT);
		SetTextColor(hDc, RGB(0, 200, 0));
		HFONT hFont = CreateFont(16, 0, 0, 0, FW_NORMAL, false, false, false, 0, 0, 0, 2, 0, "SYSTEM_FIXED_FONT");
		HFONT hTmp = (HFONT)SelectObject(hDc, hFont);
		put_text(hDc, 287, 35, "Mochimo");
		put_text(hDc, 285, 46, "Winminer v" WINMINER_VERSION);

		char buf[200];

		// Column 1

		snprintf(buf, 200, "Block: 0x%016llx", current_block);
		put_text(hDc, 139, 100, buf);

		snprintf(buf, 200, "Diff: % 6d, TX Count: % 6lld, Solved blocks: % 6d", current_diff, tx_count, blocks_solved);
		put_text(hDc, 139, 116, buf);

		snprintf(buf, 200, "Status: %s", status_str);
		put_text(hDc, 139, 132, buf);
		
		snprintf(buf, 200, "Devices: CUDA: %d, OpenCL: %d", num_cuda, num_opencl);
		put_text(hDc, 139, 148, buf);

		snprintf(buf, 200, "Haikurate: % 10llu kH/s", haikurate);
		put_text(hDc, 139, 164, buf);

		for (int i = 0; i < num_gpus; i++) {
			snprintf(buf, 200, "[GPU %2d] Temp: %3d C, Power: %6.2f W", i, gpus[i].temp, gpus[i].power / 1000.0);
			put_text(hDc, 139, 196 + i * 16, buf);
		}


		DeleteObject(hFont);
		EndPaint(hWnd, &ps);

		break;
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

VOID CALLBACK RedrawTimerProc(HWND hWnd, UINT msg, UINT timerId, DWORD dwTime) {
	BOOL res = RedrawWindow(hWnd, NULL, NULL, RDW_INVALIDATE | RDW_INTERNALPAINT);
	if (res == false) {
		printf("Redraw window failed!\n");
	}
}


void set_status(char *str) {
	strncpy(status_str, str, 64);
}