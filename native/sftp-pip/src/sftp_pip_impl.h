#pragma once
#include <string_view>
#ifndef YKM22_LUA_SFTP_PIP_IMPL_H
#define YKM22_LUA_SFTP_PIP_IMPL_H

#include <string>
#include <vector>

enum
{
    RES_ERROR_DONE = -1,
    RES_DONE = 0,
    RES_INFO = 1,
    RES_ERROR = 2,
    RES_CONTINUE = 3,
    RES_HELLO = 99,
};

enum
{
    CMD_NEW_SESSION = 0,
    CMD_UPLOADS = 1,
    CMD_DOWNLOADS = 2,
    CMD_CLOSE_SESSION = 3,
    CMD_STATUS_SESSION = 4,
    CMD_READY = 99,
    CMD_EXIT = 100,
};

struct ReqHead{
    int cmd;
    int id;
    int sessionId;
    void* session;
};

struct ResHead{
    int cmd;
    int id;
    int status;
};

void wait_working(void* session);

void get_req_head(std::string_view msgs, ReqHead& head);

using Responser = void(*)(int cmd, int id, int status, const std::string& response);

/**
1: hostname
2: username
3: password
4: port
*/
void new_session(const ReqHead& head, std::vector<std::string>& msgs, Responser response);

/**
1: local root
2: remote root
... files
*/
void uploads(const ReqHead& head, std::vector<std::string>& msgs, Responser response);

/**
1: local root
2: remote root
... files
*/
void downloads(const ReqHead& head, std::vector<std::string>& msgs, Responser response);

/**
  only head
*/
void close_session(const ReqHead& head, std::vector<std::string>& msgs, Responser response);

#endif // !YKM22_LUA_SFTP_PIP_IMPL_H
