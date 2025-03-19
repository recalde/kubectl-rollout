# **Highly Controlled Scale-Up in Kubernetes**

## **Objective**
This script is designed to perform a **highly controlled, wave-based scale-up of deployments in Kubernetes**. It ensures that:
- Deployments scale in **waves** to prevent system overload.
- Each deployment **gradually increases replicas** to avoid resource spikes.
- The system waits for all deployments in a wave to be fully **rolled out and ready** before moving forward.
- Pods are **health-checked** via HTTP before proceeding to the next wave.
- The **entire process is logged** with timestamps for tracking.

This is particularly useful in **high-availability environments** where sudden large-scale deployments can cause instability.

---

## **What This Script Does**
1. **Scales deployments in waves**, gradually increasing replicas.
2. **Waits for deployments to be fully rolled out** before proceeding.
3. **Checks pod health via HTTP probes**, ensuring readiness before moving forward.
4. **Runs a validation check on responses**, confirming expected application behavior.
5. **Logs each step with elapsed time** for easy monitoring.

---

## **High-Level Steps**
1. **Read Configuration**:
   - Deployments, selectors, wave numbers, scaling strategy, and validation settings.
   
2. **Execute in Waves**:
   - Deployments are grouped by **wave numbers** and processed in order.

3. **Scaling Phase**:
   - Each deployment scales **incrementally** with a **pause** between increases.

4. **Readiness Phase**:
   - The script **waits for deployments to complete rollout** before proceeding.

5. **Health Check Phase**:
   - HTTP health checks ensure each pod is fully functional before moving forward.

6. **Proceed to Next Wave**:
   - If all deployments in the current wave are successful, move to the next.
   - If failures occur, log them and **retry**.

---

## **How to Configure**
Modify the following arrays in the script:

```bash
# Global Configuration
ENDPOINT="/api/v1/readiness"    # Health check endpoint
VALIDATION_STRING='{"ClusterSize":4}'  # Expected response body

# Deployment Configuration
DEPLOYMENT=("deploy1" "deploy2" "deploy3")
SELECTOR=("app=my-app,instance=instance1" "app=my-app,instance=instance2" "app=my-app,instance=instance3")
WAVES=("1" "1" "2")  # Deployments grouped in waves
TARGET_REPLICAS=(10 5 15)
SCALE_DELAY=(30 20 40)  # Pause in seconds between increments
SCALE_INCREMENT=(2 3 2)  # Number of replicas added per step
WAIT_BEFORE_POLL=(15 20 30)  # Delay before HTTP health check
HTTP_PORT=(8080 9090 8000)
RETRY_DELAY=(10 15 20)  # Seconds before retrying failed health checks
MAX_RETRIES=(5 6 7)  # Maximum HTTP retries before failure
```

---

## **Detailed Rule-Based Breakdown**

### **1️⃣ Scaling Deployments**
**Rule**: Each deployment **gradually increases** replicas up to the target number.  
✅ **Why?** Prevents CPU/memory spikes in large clusters.  

- Uses `SCALE_INCREMENT[]` to add replicas step by step.  
- **Pauses** for `SCALE_DELAY[]` seconds between steps.  
- Stops once **`TARGET_REPLICAS[]` is reached**.  

> If scaling **fails**, it logs the error and stops execution.

---

### **2️⃣ Waiting for Deployment Rollout**
**Rule**: No deployment proceeds until the previous one is **fully rolled out**.  
✅ **Why?** Prevents cascading failures from unready deployments.  

- Uses **`kubectl rollout status`** to check for readiness.
- Logs **elapsed time** for tracking.
- If a deployment **fails to roll out**, execution stops.

---

### **3️⃣ Health Check via HTTP**
**Rule**: Pods must pass an **HTTP probe** before proceeding.  
✅ **Why?** Ensures application logic is working, not just container readiness.  

- Calls `http://${POD_IP}:${HTTP_PORT}/api/v1/readiness`
- Logs **only the HTTP status code** for failed requests (e.g., 401, 500).
- If **HTTP 200**, it validates the response body **against `VALIDATION_STRING`**.

---

### **4️⃣ Executing in Waves**
**Rule**: Deployments in **the same wave** are processed together.  
✅ **Why?** Ensures **controlled rollout** while maintaining stability.  

- The script **sorts deployments by `WAVES[]`**.
- **All deployments in a wave must complete** before moving to the next.

---

## **Example Execution Output**
```
[00:00] 🚀 Starting WAVE 1...
[01:00] ✅ Scaling complete for deploy1.
[01:55] ✅ Deployment deploy2 is fully rolled out.
[02:22] ✅ Pod deploy2-instance2 is ready!
✅ WAVE 1 Complete!

[02:30] 🚀 Starting WAVE 2...
[03:45] ✅ Scaling complete for deploy3.
[04:10] ✅ Deployment deploy3 is fully rolled out.
[04:25] ✅ Pod deploy3-instance3 is ready!
✅ WAVE 2 Complete!

🎉 ✅ All waves completed successfully!
```

---

## **🚀 Next Steps**
- **Test on a small scale** to verify settings.
- **Tune scale increments & delays** for optimal deployment speed.
- **Monitor logs** to confirm everything works as expected.

---

### **📌 Questions? Need Customization?**
Feel free to modify **`SCALE_INCREMENT[]`**, **`WAIT_BEFORE_POLL[]`**, or **`VALIDATION_STRING`** to fit your needs!

🚀 **Enjoy a controlled, stress-free Kubernetes deployment experience!** ✅
