using System.Collections.Generic;

using UnityEngine;
public class DollyZoom : MonoBehaviour

{

    public Transform target;  

    public new Camera camera; 

    private float initHeightAtDist; //Initial cone height

    private bool dzEnabled; 

    //Calculate the initial cone height
    float FrustumHeightAtDistance(float distance)
    {
        return 2.0f * distance * Mathf.Tan(camera.fieldOfView * 0.5f * Mathf.Deg2Rad);
    }

    //Calculate the corresponding adjustment value of FOV when the camera position is moved under a certain cone height
    float FOVForHeightAndDistance(float height, float distance)
    {
        return 2.0f * Mathf.Atan(height * 0.5f / distance) * Mathf.Rad2Deg;
    }

    //Start Dolly Zoom
    void StartDZ()
    {
        var distance = Vector3.Distance(transform.position, target.position);
        initHeightAtDist = FrustumHeightAtDistance(distance);
        dzEnabled = true;
    }

    //StopDolly Zoom
    void StopDZ()
    {
        dzEnabled = false;
    }

    void Start()
    {
        StartDZ();
    }
    void Update()
    {
        if (dzEnabled)
        {
            //According to the distance between the camera and the target object, the FOV value of the camera is calculated and adjusted
            var currDistance = Vector3.Distance(transform.position, target.position);
            camera.fieldOfView = FOVForHeightAndDistance(initHeightAtDist, currDistance);
        }
        //Move the camera back and forth
        transform.Translate(Input.GetAxis("Vertical") * Vector3.forward * Time.deltaTime * 5f);
    }
}
