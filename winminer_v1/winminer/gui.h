#pragma once

#include <Windows.h>

int WINAPI start_gui_thread();
int check_gui_thread_alive();
void set_status(char *str);
