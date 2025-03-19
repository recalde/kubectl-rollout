package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sort"
	"strings"
	"time"
)

// Structs for Configuration
type Config struct {
	Deployments []Deployment `json:"deployments"`
}

type Deployment struct {
	Name             string       `json:"name"`
	InitialReplicas  int          `json:"initialReplicas"`
	MaxReplicas      int          `json:"maxReplicas"`
	ScaleStep        int          `json:"scaleStep"`
	ScaleInterval    string       `json:"scaleInterval"`
	Wave             int          `json:"wave"`
	ReadinessTimeout string       `json:"readinessTimeout"`
	MaxRetries       int          `json:"maxRetries"`
	Validation       Validation   `json:"validation"`
}

type Validation struct {
	Type            string            `json:"type"`
	URL             string            `json:"url"`
	Method          string            `json:"method"`
	ValidationDelay string            `json:"validationDelay"`
	Body            string            `json:"body,omitempty"`
	Headers         map[string]string `json:"headers,omitempty"`
	Check           CheckCondition    `json:"check"`
}

type CheckCondition struct {
	Field    string      `json:"field"`
	Condition string     `json:"condition"`
	Value    interface{} `json:"value"`
}

type Pod struct {
	Name string
	IP   string
}

// Icons for Fun and Clarity 🎩
const (
	checkMark   = "✅"
	warning     = "⚠️"
	errorMark   = "❌"
	waiting     = "⏳"
	progressDot = "🔄"
	rocket      = "🚀"
	magicHat    = "🎩" // Surprise new icon: Magic hat when things work magically!
)

// Global Start Time for Logging
var startTime = time.Now()

func main() {
	logMessage(rocket, "Starting Pod Scaler...")

	// Load configuration
	config, err := loadConfig("/config/deployments.yaml")
	if err != nil {
		log.Fatalf("%s Failed to load config: %v", errorMark, err)
	}

	// Group deployments by wave
	waveMap := groupByWave(config.Deployments)

	// Process waves sequentially
	for wave, deployments := range waveMap {
		logMessage(rocket, "Starting wave %d...", wave)
		scaleDeploymentsRoundRobin(deployments)
		logMessage(waiting, "Wave %d scaling complete. Waiting for readiness...", wave)
		waitForDeployments(deployments)
		logMessage(checkMark, "Wave %d ready. Proceeding to validation...", wave)
		validatePods(deployments)
	}

	logMessage(magicHat, "All waves completed successfully!")
}

// Load configuration from file
func loadConfig(path string) (Config, error) {
	var config Config
	data, err := ioutil.ReadFile(path)
	if err != nil {
		return config, err
	}
	err = json.Unmarshal(data, &config)
	return config, err
}

// Group deployments by wave
func groupByWave(deployments []Deployment) map[int][]Deployment {
	waveMap := make(map[int][]Deployment)
	for _, d := range deployments {
		waveMap[d.Wave] = append(waveMap[d.Wave], d)
	}
	return waveMap
}

// Scale up deployments round-robin within a wave
func scaleDeploymentsRoundRobin(deployments []Deployment) {
	anyScaled := true
	for anyScaled {
		anyScaled = false
		for i, d := range deployments {
			currentReplicas := getDeploymentReplicas(d.Name)
			if currentReplicas < d.MaxReplicas {
				newReplicas := min(currentReplicas+d.ScaleStep, d.MaxReplicas)
				scaleDeployment(d.Name, newReplicas)
				logMessage(checkMark, "Scaled %s to %d replicas", d.Name, newReplicas)
				anyScaled = true
			}
			if i < len(deployments)-1 {
				time.Sleep(parseDuration(d.ScaleInterval))
			}
		}
	}
}

// Get deployment replica count
func getDeploymentReplicas(name string) int {
	out, err := exec.Command("kubectl", "get", "deployment", name, "-o", "jsonpath={.spec.replicas}").Output()
	if err != nil {
		logMessage(errorMark, "Failed to get replicas for %s", name)
		return 0
	}
	var replicas int
	fmt.Sscanf(string(out), "%d", &replicas)
	return replicas
}

// Scale a deployment
func scaleDeployment(name string, replicas int) {
	_ = exec.Command("kubectl", "scale", "deployment", name, fmt.Sprintf("--replicas=%d", replicas)).Run()
}

// Wait for deployments to be ready with timeout
func waitForDeployments(deployments []Deployment) {
	for _, d := range deployments {
		timeout := parseDuration(d.ReadinessTimeout)
		start := time.Now()

		for {
			if time.Since(start) > timeout {
				logMessage(errorMark, "Timeout reached for %s. Proceeding anyway...", d.Name)
				break
			}

			out, err := exec.Command("kubectl", "get", "deployment", d.Name, "-o", "jsonpath={.status.readyReplicas}").Output()
			if err == nil && strings.TrimSpace(string(out)) == fmt.Sprint(d.MaxReplicas) {
				break
			}
			logMessage(waiting, "Waiting for %s to be ready...", d.Name)
			time.Sleep(10 * time.Second)
		}
	}
}

// Validate Pods
func validatePods(deployments []Deployment) {
	for _, d := range deployments {
		pods := getPods(d.Name)
		retries := d.MaxRetries

		for retries > 0 && len(pods) > 0 {
			time.Sleep(parseDuration(d.Validation.ValidationDelay))

			for i := 0; i < len(pods); i++ {
				p := pods[i]
				if validatePod(p, d.Validation) {
					logMessage(checkMark, "Pod %s (%s) passed validation", p.Name, p.IP)
					pods = append(pods[:i], pods[i+1:]...)
					i--
				}
			}

			if len(pods) > 0 {
				logMessage(warning, "Retrying validation for %d pods (%d retries left)...", len(pods), retries-1)
				time.Sleep(10 * time.Second)
			}

			retries--
		}

		if len(pods) > 0 {
			logMessage(errorMark, "Some pods failed validation after %d retries: %v", d.MaxRetries, pods)
		}
	}
}

// Universal Logging Function with MM:SS timestamp
func logMessage(icon string, format string, args ...interface{}) {
	elapsed := time.Since(startTime)
	fmt.Printf("[%02d:%02d] %s %s\n",
		int(elapsed.Minutes()), int(elapsed.Seconds())%60, icon, fmt.Sprintf(format, args...))
}

// Helper Functions
func parseDuration(d string) time.Duration { dur, _ := time.ParseDuration(d); return dur }
func min(a, b int) int                     { if a < b { return a } else { return b } }
