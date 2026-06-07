#include <iostream>
#include <string>
#include <fstream>
#include <chrono>
#include <thread>
#include <atomic>
#include <time.h>
#include <iomanip>
#include <filesystem>
#include <curl/curl.h>

using namespace std;

/* | DONT FORGET TO COMPILE WITH -lcurl | */

// Enables Debug output
//#define DEBUG 1

// Disables Willhaben Querys
//#define NOQUERY 1

// Filenames
string KnownLinksFile = "link_list.txt";
string SearchagentsFile = "searchagents.xml";
string BotDataFile = "Telegram_Bot_Data.xml";
string FolderForTemporaryData = "TempData";

atomic<bool> running(true);  // Atomic flag to control loop

///////////////////////////////////////////
/// FUNCTION DEFINITIONS
void SendTelegramNotification(string message);
void RunSearchagent(string name, string link);
void GetData(string link, string path);
void AnalyzeData(string path, string name);
void CheckInput();
string GetTimestamp();
string ReadFileToString(basic_string<char> filename);
void CheckFileIntegrity();
size_t DiscardCallback(void* contents, size_t size, size_t nmemb, void* userp);
///////////////////////////////////////////

int main() {
    curl_global_init(CURL_GLOBAL_DEFAULT);  // Init curl once at startup

    cout << endl;
    cout << GetTimestamp() << "Starting..." << endl;
    #ifdef DEBUG
    cout << "\033[7m" << GetTimestamp() << "started main\033[0m" << endl;
    #endif

    CheckFileIntegrity();
    cout << GetTimestamp() << "[ \033[1;32m\u2714\033[0m ] File structure is intact." << endl;

    int rerunmins = 30;
    thread inputThread(CheckInput);  // Run input check in separate thread

    string name;
    string link;
    string searchagents;

    string TelegramMessage = "Das Programm wurde Gestartet.\nDas Updateinterval beträgt *" + to_string(rerunmins) + "* Minuten.";
    SendTelegramNotification(TelegramMessage);
    cout << GetTimestamp() << "Type \"stop\" to Shut down the searchagent." << endl;

    auto sleep_duration = chrono::minutes(rerunmins);
    auto check_interval = chrono::seconds(1);

    while (running) {
        #ifdef DEBUG
        cout << "\033[7m" << GetTimestamp() << "starting while loop\033[0m\n";
        #endif

        searchagents = ReadFileToString(SearchagentsFile);

        #ifdef DEBUG
        cout << "\033[7m" << GetTimestamp() << "read searchagents\033[0m\n";
        #endif

        while (searchagents.find("<link>") != string::npos) {
            #ifdef DEBUG
            cout << "\033[7m" << GetTimestamp() << "reading through searchagents\033[0m\n";
            #endif

            size_t nameStart = searchagents.find("<name>") + 6;
            size_t nameEnd   = searchagents.find("</name>");
            size_t linkStart = searchagents.find("<link>") + 6;
            size_t linkEnd   = searchagents.find("</link>");

            if (nameEnd == string::npos || linkEnd == string::npos) break;

            name = searchagents.substr(nameStart, nameEnd - nameStart);
            link = searchagents.substr(linkStart, linkEnd - linkStart);

            RunSearchagent(name, link);
            searchagents = searchagents.substr(linkEnd + 7);  // +7 = length of "</link>"
        }

        for (auto elapsed = chrono::seconds(0); elapsed < sleep_duration; elapsed += check_interval) {
            this_thread::sleep_for(check_interval);
            if (!running) break;
        }
    }

    inputThread.join();
    curl_global_cleanup();  // Cleanup curl once at shutdown
    cout << GetTimestamp() << "Program has successfully stopped." << endl;

    return 0;
}

string ReadFileToString(basic_string<char> filename) {
    #ifdef DEBUG
    cout << "\033[7m" << GetTimestamp() << "reading file to string: " << filename << "\033[0m\n";
    #endif

    ifstream filedata(filename);
    if (!filedata.is_open()) {
        cout << GetTimestamp() << "Error reading file: " << filename << endl;
        return "";
    }

    string data((istreambuf_iterator<char>(filedata)),
                 istreambuf_iterator<char>());
    return data;
}

void RunSearchagent(string name, string link) {
    #ifdef DEBUG
    cout << "\033[7m" << GetTimestamp() << "running searchagent\033[0m\n";
    #endif

    string path = "./" + FolderForTemporaryData + "/" + name + ".html";
    #ifndef NOQUERY
    GetData(link, path);
    AnalyzeData(path, name);
    #endif
}

void AnalyzeData(string path, string name) {
    #ifdef DEBUG
    cout << "\033[7m" << GetTimestamp() << "analyzing data\033[0m\n";
    #endif

    string stored_links = ReadFileToString(KnownLinksFile);
    this_thread::sleep_for(chrono::seconds(1));
    string data = ReadFileToString(path);

    if (data.empty()) {
        #ifndef DEBUG
        cout << "\033[F\033[2K";
        #endif
        cout << GetTimestamp() << "[ \033[1;31m\u2716\033[0m ] No data received for: " << name << endl;
        cout << GetTimestamp() << "Type \"stop\" to Shut down the searchagent." << endl;
        filesystem::remove(path);  // clean up the empty file
        return;
    }

    string ProductID;

    // Open link file once, outside the loop
    ofstream link_file(KnownLinksFile, ios::app);
    if (!link_file.is_open()) {
        cerr << GetTimestamp() << "Failed to open link list file for writing." << endl;
        return;
    }

    while (data.find("https://www.willhaben.at/iad/object?adId=") != string::npos) {
        size_t adPos = data.find("https://www.willhaben.at/iad/object?adId=") + 41;
        data = data.substr(adPos);
        ProductID = data.substr(0, data.find_first_of("\""));

        if (ProductID.empty()) continue;

        if (stored_links.find(ProductID) == string::npos) {
            #ifdef DEBUG
            cout << "\033[7m" << GetTimestamp() << "new link found\033[0m\n";
            #endif

            SendTelegramNotification(
                "*Suchagent " + name + ".*\nEine neue Anzeige ist verf%C3%BCgbar. Link:\n"
                "https://www.willhaben.at/iad/object?adId=" + ProductID
            );

            link_file << GetTimestamp() << ProductID << "\n";
            link_file.flush();  // Ensure it's written before we read it next iteration

            // Update our in-memory copy so we don't re-report it this run
            stored_links += ProductID + "\n";

            #ifndef DEBUG
            cout << "\033[F\033[2K";
            #endif
            cout << GetTimestamp() << "[ \033[1;32m\u2714\033[0m ] added product ID | ID=" << ProductID << endl;
            cout << GetTimestamp() << "Type \"stop\" to Shut down the searchagent." << endl;
            this_thread::sleep_for(chrono::seconds(1));
        }
    }

    link_file.close();
    this_thread::sleep_for(chrono::seconds(3));

    if (filesystem::remove(path)) {
        #ifdef DEBUG
        cout << "\033[7m" << GetTimestamp() << path << " successfully deleted\033[0m\n";
        #endif
    } else {
        #ifdef DEBUG
        cout << "\033[7m" << GetTimestamp() << path << " could not be deleted\033[0m\n";
        #endif
    }
}

// Intentionally discards response body (used for Telegram API calls)
size_t DiscardCallback(void* contents, size_t size, size_t nmemb, void* userp) {
    (void)contents; (void)userp;
    return size * nmemb;
}

void GetData(const string link, const string path) {
    #ifdef DEBUG
    cout << "\033[7m" << GetTimestamp() << "Getting data from: " << link << "\033[0m" << endl;
    #endif

    CURL* curl = curl_easy_init();
    if (!curl) {
        cerr << GetTimestamp() << "Failed to initialize CURL!" << endl;
        return;
    }

    FILE* file = fopen(path.c_str(), "wb");
    if (!file) {
        cerr << GetTimestamp() << "Failed to open file for writing: " << path << endl;
        curl_easy_cleanup(curl);
        return;
    }

    curl_easy_setopt(curl, CURLOPT_URL, link.c_str());
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, NULL);  // use libcurl's default writer
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, file);      // writes directly to FILE*
    curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
    curl_easy_setopt(curl, CURLOPT_USERAGENT, "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36");
    curl_easy_setopt(curl, CURLOPT_REFERER, "https://www.willhaben.at/");

    // Log HTTP response code in debug mode
    #ifdef DEBUG
    long http_code = 0;
    curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
    cout << "\033[7m" << GetTimestamp() << "HTTP response code: " << http_code << "\033[0m" << endl;
    #endif

    CURLcode res = curl_easy_perform(curl);
    if (res != CURLE_OK) {
        cerr << GetTimestamp() << "CURL request failed: " << curl_easy_strerror(res) << endl;
    }

    fclose(file);
    curl_easy_cleanup(curl);
}

void SendTelegramNotification(const string message) {
    string data = ReadFileToString(BotDataFile);
    if (data.empty()) return;

    size_t tokenStart = data.find("<API_Token>") + 11;
    size_t tokenEnd   = data.find("</API_Token>");
    size_t chatStart  = data.find("<ChatID>") + 8;
    size_t chatEnd    = data.find("</ChatID>");

    if (tokenEnd == string::npos || chatEnd == string::npos) {
        cerr << GetTimestamp() << "Failed to parse bot data file." << endl;
        return;
    }

    string TelegramAPIToken = data.substr(tokenStart, tokenEnd - tokenStart);
    string TelegramChatID   = data.substr(chatStart,  chatEnd  - chatStart);

    string url      = "https://api.telegram.org/bot" + TelegramAPIToken + "/sendMessage";
    string postData = "chat_id=" + TelegramChatID + "&parse_mode=Markdown&text=" + message;

    CURL* curl = curl_easy_init();
    if (curl) {
        curl_easy_setopt(curl, CURLOPT_URL, url.c_str());
        curl_easy_setopt(curl, CURLOPT_POSTFIELDS, postData.c_str());
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, DiscardCallback);  // discard response
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);

        CURLcode res = curl_easy_perform(curl);
        if (res != CURLE_OK) {
            cerr << GetTimestamp() << "Telegram curl request failed: " << curl_easy_strerror(res) << endl;
        }

        curl_easy_cleanup(curl);
    }
}

void CheckInput() {
    #ifdef DEBUG
    cout << "\033[7m" << GetTimestamp() << "checking for input\033[0m\n";
    #endif

    string input;
    while (true) {
        cin >> input;
        if (input == "stop") {
            running = false;
            break;
        } else {
            cout << GetTimestamp() << "Unknown command: " << input << endl;
        }
    }
}

string GetTimestamp() {
    time_t theTime = time(NULL);
    struct tm* aTime = localtime(&theTime);

    stringstream ss;
    ss << setw(4) << setfill('0') << (aTime->tm_year + 1900) << "."
       << setw(2) << setfill('0') << (aTime->tm_mon + 1)     << "."
       << setw(2) << setfill('0') <<  aTime->tm_mday         << "|"
       << setw(2) << setfill('0') <<  aTime->tm_hour         << ":"
       << setw(2) << setfill('0') <<  aTime->tm_min          << "."
       << setw(2) << setfill('0') <<  aTime->tm_sec          << "| ";
    return ss.str();
}

void CheckFileIntegrity() {
    #ifdef DEBUG
    cout << "\033[7m" << GetTimestamp() << "checking file integrity\033[0m\n";
    #endif

    bool error = false;

    if (!filesystem::exists(FolderForTemporaryData)) {
        if (filesystem::create_directory(FolderForTemporaryData)) {
            cout << GetTimestamp() << "Directory created: " << FolderForTemporaryData << "\n";
        } else {
            cerr << GetTimestamp() << "Failed to create directory: " << FolderForTemporaryData << "\n";
        }
    }

    if (!filesystem::exists(KnownLinksFile)) {
        ofstream createfile(KnownLinksFile);
        if (createfile) {
            cout << GetTimestamp() << "link list file created." << endl;
            createfile << "known ads will be saved here" << endl;
        }
    }

    if (filesystem::exists(SearchagentsFile)) {
        string content = ReadFileToString(SearchagentsFile);
        string tmp = content;
        while (tmp.find("<link>") != string::npos) {
            size_t linkStart = tmp.find("<link>") + 6;
            size_t linkEnd   = tmp.find("</link>");
            if (linkEnd == string::npos) break;

            string link = tmp.substr(linkStart, linkEnd - linkStart);
            tmp = tmp.substr(linkEnd + 7);

            if (link == "Insert link here") {
                cout << GetTimestamp() << "[ \033[1;31m\u2716\033[0m ] please fill out the searchagents file." << endl;
                error = true;
            }
        }
    } else {
        ofstream createfile(SearchagentsFile);
        if (createfile) {
            createfile << "Add searchagents as seen in the following schematic:\n"
                       << "<searchagents>\n"
                       << "\t<searchagent>\n"
                       << "\t\t<name>Insert name here (without whitespaces)</name>\n"
                       << "\t\t<link>Insert link here</link>\n"
                       << "\t</searchagent>\n"
                       << "</searchagents>\n";
        }
        cout << GetTimestamp() << "[ \033[1;31m\u2716\033[0m ] searchagents file created. Please fill it with data." << endl;
        error = true;
    }

    if (filesystem::exists(BotDataFile)) {
        string data = ReadFileToString(BotDataFile);
        size_t tokenStart = data.find("<API_Token>") + 11;
        size_t tokenEnd   = data.find("</API_Token>");
        if (tokenEnd != string::npos) {
            string token = data.substr(tokenStart, tokenEnd - tokenStart);
            if (token == "Insert API token") {
                cout << GetTimestamp() << "[ \033[1;31m\u2716\033[0m ] please fill out the Bot Data file." << endl;
                error = true;
            }
        }
    } else {
        ofstream createfile(BotDataFile);
        if (createfile) {
            createfile << "<Bot-Data>\n"
                       << "\t<API_Token>Insert API token</API_Token>\n"
                       << "\t<ChatID>Insert chat ID</ChatID>\n"
                       << "</Bot-Data>\n";
        }
        cout << GetTimestamp() << "[ \033[1;31m\u2716\033[0m ] Bot Data file created. Please enter your data." << endl;
        error = true;
    }

    if (error) {
        cout << GetTimestamp() << "[ \033[1;31m\u2716\033[0m ] Exiting. Did not pass the integrity check." << endl;
        exit(1);
    }
}