#include "sleep.h"

#include <Windows.h>

void msleep(uint32_t milliseconds) {
	Sleep(milliseconds);
}