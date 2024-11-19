extends Node

const GITHUB_API_URL = "https://api.github.com"
const OWNER = "FNF-CNE-Devs"
const REPO = "CodenameEngine"
const MAX_WORKFLOWS = 100
const GITHUB_TOKEN = ""
const TEMP_DIR = "temp"
const DOWNLOAD_DIR = "downloads/" + REPO + "-" + OWNER
const API_DOWNLOAD_URL = "https://github.com/%s/%s/archive/%s.zip"
const ARTIFACTS_API_URL = GITHUB_API_URL + "/repos/%s/%s/actions/runs/%s/artifacts"

@onready var commit_name = $"../Git Text Group/git-commit-name"
@onready var workflow_name = $"../Git Text Group/git-workflow-name"
@onready var trigger_commit = $"../Git Text Group/git-trigger-name"
@onready var author_name = $"../Git Text Group/git-author-name2"
@onready var commit_hash = $"../Git Text Group/git-author-name3"
@onready var page_counter = $"../Git Text Group/page-counter"
@onready var left_text = $"../Download Text Group/dl text"
@onready var middle_text = $"../Download Text Group/dl text2"
@onready var right_text = $"../Download Text Group/dl text3"

var http_request: HTTPRequest
var artifact_request: HTTPRequest
var download_request: HTTPRequest
var current_workflow_index = 0
var workflow_runs = []
var download_start_time: float = 0.0
var download_size: float = 0.0
var downloaded_bytes: float = 0.0
var is_downloading: bool = false
var total_bytes: float = 0.0
var download_retries: int = 0
const MAX_RETRIES = 1

func _ready():
	http_request = HTTPRequest.new()
	artifact_request = HTTPRequest.new()
	download_request = HTTPRequest.new()
	download_request.use_threads = true
	download_request.download_chunk_size = 4096
	download_request.body_size_limit = -1
	download_request.timeout = 0
	
	add_child(http_request)
	add_child(artifact_request)
	add_child(download_request)
	
	http_request.request_completed.connect(_on_request_completed)
	artifact_request.request_completed.connect(_on_artifact_request_completed)
	download_request.request_completed.connect(_on_download_completed)
	download_request.connect("request_progress", _on_download_progress)
	
	fetch_workflow_info()
	update_page_counter()

func fetch_workflow_info():
	var headers = []
	if GITHUB_TOKEN != "":
		headers = ["Authorization: Bearer " + GITHUB_TOKEN]
	
	var endpoint = "/repos/%s/%s/actions/runs?per_page=%d" % [OWNER, REPO, MAX_WORKFLOWS]
	var url = GITHUB_API_URL + endpoint
	
	var error = http_request.request(url, headers)
	if error != OK:
		print("An error occurred in the HTTP request.")

func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Failed to get workflow information")
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json.has("workflow_runs"):
		print("No workflow runs found")
		return
	
	workflow_runs = json.workflow_runs
	update_workflow_display()

func get_first_line(text: String) -> String:
	var lines = text.split("\n")
	return lines[0].strip_edges()

func truncate_text(text: String, max_length: int) -> String:
	if text.length() <= max_length:
		return text
	return text.substr(0, max_length - 3) + "..."

func update_workflow_display():
	if workflow_runs.size() == 0:
		return
	
	var current_run = workflow_runs[current_workflow_index]
	
	var commit_message = get_first_line(current_run.head_commit.message)
	
	var truncated_commit = truncate_text(commit_message, 33)
	var truncated_workflow = truncate_text(current_run.name, 30)
	var truncated_author = truncate_text(current_run.actor.login, 20)
	
	commit_name.text = truncated_commit
	workflow_name.text = "Workflow: " + truncated_workflow
	trigger_commit.text = "Triggering Commit: " + commit_message
	author_name.text = "Author: " + truncated_author
	commit_hash.text = "Commit Hash: " + current_run.head_sha.substr(0, 7)
	
	update_download_info()
	update_page_counter()

func update_page_counter():
	var total = workflow_runs.size()
	var current = current_workflow_index + 1 if total > 0 else 0
	page_counter.text = "%d/%d" % [current, total]

func _input(event):
	if event.is_action_pressed("ui_left"):
		change_workflow(-1)
	elif event.is_action_pressed("ui_right"):
		change_workflow(1)
	elif event.is_action_pressed("ui_accept"):
		download_current_workflow()

func change_workflow(direction):
	if workflow_runs.size() == 0:
		return
	
	current_workflow_index = (current_workflow_index + direction) % workflow_runs.size()
	if current_workflow_index < 0:
		current_workflow_index = workflow_runs.size() - 1
	
	update_workflow_display()

func download_current_workflow():
	if workflow_runs.size() == 0 or is_downloading:
		return
		
	var current_run = workflow_runs[current_workflow_index]
	if current_run.head_sha == "Loading..." or current_run.head_sha == "N/A":
		return
		
	is_downloading = true
	download_start_time = Time.get_unix_time_from_system()
	download_retries = 0
	
	_attempt_download()

func _on_artifact_request_completed(result, response_code, response_headers, body):
	if response_code != 200:
		print("Failed to get artifacts")
		right_text.text = "Failed! No artifacts"
		is_downloading = false
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or json.size() == 0:
		print("No artifacts found")
		right_text.text = "Failed! No artifacts"
		is_downloading = false
		return
		
	var artifact = json[0]
	var download_url = artifact.url
	print("Starting artifact download from: ", download_url)
	
	var download_headers = [
		"User-Agent: GodotEngine",
		"Accept: application/zip"
	]
	
	right_text.text = "Starting download..."
	var error = download_request.request(download_url, download_headers)
	if error != OK:
		print("Failed to start download")
		right_text.text = "Failed to start download!"
		is_downloading = false

func _on_download_completed(result, response_code, headers, body):
	print("Download completed with result: ", result)
	print("Response code: ", response_code)
	print("Headers: ", headers)
	print("Body size: ", body.size() if body != null else "null")
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_download_error("Error: %d (%s)" % [result, error_string(result)])
		return
	
	if response_code != 200:
		right_text.text = "Failed! HTTP %d" % response_code
		print("Failed to download. Response code: ", response_code)
		return
	
	if body.size() == 0:
		right_text.text = "Failed! Empty download"
		print("Download failed: Empty body")
		return
	
	var base_dir = OS.get_executable_path().get_base_dir()
	var dir = DirAccess.open(base_dir)
	
	if not dir.dir_exists(TEMP_DIR):
		dir.make_dir_recursive(TEMP_DIR)
	
	var zip_path = base_dir.path_join(TEMP_DIR).path_join("download.zip")
	print("Saving downloaded file to: ", zip_path)
	
	var zip_file = FileAccess.open(zip_path, FileAccess.WRITE)
	if zip_file == null:
		right_text.text = "Failed to write file!"
		print("Failed to create zip file")
		return
	
	zip_file.store_buffer(body)
	zip_file.close()
	print("File saved successfully, size: ", body.size(), " bytes")
	
	var target_dir = base_dir.path_join(DOWNLOAD_DIR)
	if not dir.dir_exists(DOWNLOAD_DIR):
		dir.make_dir_recursive(DOWNLOAD_DIR)
	
	print("Extracting files to: ", target_dir)
	var zip_reader = ZIPReader.new()
	var error = zip_reader.open(zip_path)
	
	if error != OK:
		right_text.text = "Failed to open zip!"
		print("Failed to open zip file, error: ", error)
		return
	
	var files = zip_reader.get_files()
	print("Found ", files.size(), " files in archive")
	
	var extracted_count = 0
	var total_files = files.size()
	
	for file_name in files:
		extracted_count += 1
		var progress = int((float(extracted_count) / total_files) * 100)
		right_text.text = "Extracting... %d%%" % progress
		
		var content = zip_reader.read_file(file_name)
		var target_path = target_dir.path_join(file_name)
		
		var file_dir = target_path.get_base_dir()
		if not dir.dir_exists(file_dir):
			dir.make_dir_recursive(file_dir)
		
		var out_file = FileAccess.open(target_path, FileAccess.WRITE)
		if out_file != null:
			out_file.store_buffer(content)
			out_file.close()
			print("Extracted: ", file_name)
	
	zip_reader.close()
	cleanup_temp()
	
	var elapsed = int(Time.get_unix_time_from_system() - download_start_time)
	right_text.text = "Done! | %ds" % elapsed

func _on_download_progress(bytes_downloaded: float, bytes_total: float):
	downloaded_bytes = bytes_downloaded
	total_bytes = bytes_total
	
	var progress = 0
	if total_bytes > 0:
		progress = int((downloaded_bytes / total_bytes) * 100)
	
	var elapsed = int(Time.get_unix_time_from_system() - download_start_time)
	
	right_text.text = "Downloading... %d%% | %ds" % [progress, elapsed]

func cleanup_temp():
	var base_dir = OS.get_executable_path().get_base_dir()
	var dir = DirAccess.open(base_dir)
	if dir.dir_exists(TEMP_DIR):
		dir.change_dir(TEMP_DIR)
		var files = dir.get_files()
		for file_name in files:
			dir.remove(file_name)
		dir.change_dir("..")
		dir.remove(TEMP_DIR)
		print("Cleaned up temporary files")

func _process(_delta):
	pass 

func update_download_info():
	if workflow_runs.size() == 0:
		return
	
	var current_run = workflow_runs[current_workflow_index]
	
	left_text.text = truncate_text(REPO, 9)
	middle_text.text = "%s/%s (%s)" % [OWNER, REPO, current_run.head_sha.substr(0, 7)]
	
	if not is_downloading:
		right_text.text = "Ready | 0s"

func _handle_download_error(error_message: String):
	download_retries += 1
	
	if download_retries < MAX_RETRIES:
		print("Download attempt %d failed: %s" % [download_retries, error_message])
		right_text.text = "Retrying... (%d/%d)" % [download_retries, MAX_RETRIES]
		await get_tree().create_timer(1.0).timeout
		_attempt_download()
	else:
		print("Download failed after %d attempts: %s" % [MAX_RETRIES, error_message])
		right_text.text = error_message
		is_downloading = false

func _attempt_download():
	var current_run = workflow_runs[current_workflow_index]
	
	var download_url = API_DOWNLOAD_URL % [OWNER, REPO, current_run.head_sha]
	print("Starting download from: ", download_url)
	
	var download_headers = [
		"User-Agent: FunkinLauncher",
		"Accept: application/zip"
	]
	
	right_text.text = "Starting download..."
	var error = download_request.request(download_url, download_headers)
	if error != OK:
		print("Failed to start download: ", error_string(error))
		_handle_download_error("Failed to start download!")
		return
