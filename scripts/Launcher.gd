extends Node

const GITHUB_API_URL = "https://api.github.com"
const OWNER = "FNF-CNE-Devs"
const REPO = "CodenameEngine"

@onready var commit_name = $"../Git Text Group/git-commit-name"
@onready var workflow_name = $"../Git Text Group/git-workflow-name"
@onready var trigger_commit = $"../Git Text Group/git-trigger-name"
@onready var author_name = $"../Git Text Group/git-author-name2"
@onready var commit_hash = $"../Git Text Group/git-author-name3"

var http_request: HTTPRequest

func _ready():
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)
	
	fetch_workflow_info()

func fetch_workflow_info():
	var headers = []	
	var endpoint = "/repos/%s/%s/actions/runs" % [OWNER, REPO]
	var url = GITHUB_API_URL + endpoint
	
	var error = http_request.request(url, headers)
	if error != OK:
		print("An error occurred in the HTTP request.")

func _on_request_completed(result, response_code, headers, body):
	if response_code != 200:
		print("Failed to get workflow information")
		return
	
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json == null or not json.has("workflow_runs") or json.workflow_runs.size() == 0:
		print("No workflow runs found")
		return
	
	var latest_run = json.workflow_runs[0]
	
	commit_name.text = latest_run.head_commit.message
	workflow_name.text = "Workflow: " + latest_run.name
	trigger_commit.text = "Triggering Commit: " + latest_run.head_commit.message
	author_name.text = "Author: " + latest_run.actor.login
	commit_hash.text = "Commit Hash: " + latest_run.head_sha.substr(0, 7)

func _process(_delta):
	pass 
