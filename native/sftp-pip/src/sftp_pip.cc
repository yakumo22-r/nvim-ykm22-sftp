/**
  sftp program
  interface for pip

  [ ] custom port
  [ ] review/clean code
*/
#include "fmt/base.h"
#include "fmt/format.h"
#include <algorithm>
#include <csignal>
#include <cstddef>
#include <cstdlib>
#include <iostream>
#include <atomic>
#include <mutex>
#include <queue>
#include <string>
#include <thread>
#include <vector>
#include "libssh/libssh.h"
#include "sftp_pip_impl.h"

std::atomic<bool> running(true);
void signal_handler(int signal) { running = false; }

void process_handle(std::vector<std::string>& msgs);

struct Task
{
    Task() = default;
    Task(std::vector<std::string>&& args) : args(std::move(args)) {}
    std::vector<std::string> args;
};

std::mutex cout_mutex;

std::mutex taskQueue_mutex;
std::queue<Task> taskQueue;
std::condition_variable taskQueue_condition;

// Remove leading and trailing whitespace from a string_view, return string
std::string trim(std::string_view str)
{
    // Find first non-whitespace character
    auto start = std::find_if(str.begin(), str.end(), [](unsigned char ch) { return !std::isspace(ch); });

    // Find last non-whitespace character
    auto end = std::find_if(str.rbegin(), str.rend(), [](unsigned char ch) { return !std::isspace(ch); }).base();

    // Return trimmed string
    return std::string(start, end);
}

void response(int cmd, int id, int status, const std::string& response);

void task_thread()
{
    while (running)
    {
        Task task;
        {

            std::unique_lock<std::mutex> lock(taskQueue_mutex);
            taskQueue_condition.wait(lock, [] { return !taskQueue.empty() || !running; });
            if (!running) { return; }
            task = std::move(taskQueue.front());
            taskQueue.pop();
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        for (auto& arg : task.args)
        {
            if (trim(arg) == "#") { arg.clear(); }
        }
        process_handle(task.args);
    }
}


#define SFTP_PIP_VERSION "version 0.0.7"

int main()
{
#ifdef _WIN32
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
#else
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);
#endif
    ssh_init();

    std::thread worker(task_thread);
    worker.detach();

    std::string line;
    std::vector<std::string> msgs;
    response(CMD_READY, 0, RES_HELLO, SFTP_PIP_VERSION);
    while (running && std::getline(std::cin, line))
    {
        if (std::cin.eof()) { break; }

        if (line == "")
        {
            {
                std::lock_guard<std::mutex> lock(taskQueue_mutex);
                taskQueue.emplace(std::move(msgs));
            }
            taskQueue_condition.notify_one();
        }
        else { msgs.emplace_back(line); }
    }

    running = false;
    taskQueue_condition.notify_all();
    ssh_finalize();
    return 0;
}

// std::mutex cout_mutex;
void response(int cmd, int id, int status, const std::string& response)
{
    std::lock_guard<std::mutex> lock(cout_mutex);
    auto res = fmt::format("{} {} {}\n{}\n\n", cmd, id, status, response =="" ? "#" : response);
    std::cout << res << std::flush;
}

void process_handle(std::vector<std::string>& msgs)
{

    if (msgs.size() < 1) { return; }
    ReqHead head;
    std::string msg = "";
    get_req_head(msgs[0], head);
    switch (head.cmd)
    {
    case CMD_NEW_SESSION:
        new_session(head, msgs, response);
        break;
    case CMD_UPLOADS:
        uploads(head, msgs, response);
        break;
    case CMD_DOWNLOADS:
        downloads(head, msgs, response);
        break;
    case CMD_CLOSE_SESSION:
        close_session(head, msgs, response);
        break;
    case CMD_EXIT:
        response(CMD_EXIT, head.id, RES_DONE, "exit");
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
        running = false;
        std::exit(0);
        break;
    }
};
