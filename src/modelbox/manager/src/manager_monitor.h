/*
 * Copyright 2021 The Modelbox Project Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#ifndef MODELBOX_MANAGER_MONITOR_H
#define MODELBOX_MANAGER_MONITOR_H

#include "manager_common.h"

#ifdef __cplusplus
extern "C" {
#endif /*__cplusplus */

int manager_monitor_init(void);

int app_start(const char *name, const char *cmdline, const char *pidfile,
              int no_check);

int app_stop(const char *name, int gracefull);

int app_alive(const char *name);

int app_getpid(const char *name);

int app_monitor(void);

int manager_monitor_exit(void);

#ifdef BUILD_TEST

struct app_monitor;
struct Test_App;

void app_free_memory(void);

void app_test(struct app_monitor *app);
typedef int (*app_child_func)(struct Test_App *child, int count,
                              const char *name);
struct Test_App {
  app_child_func run;
  void *arg1;
  void *arg2;
  void *arg3;
};
extern struct Test_App test_app;
#endif

#ifdef __cplusplus
}
#endif /*__cplusplus */

#endif  // !MODELBOX_MANAGER_MONITOR_H