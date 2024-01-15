using System.Collections;
using System.Collections.Generic;
using Cinemachine;
using UnityEngine;
using UnityTemplateProjects;

public class SwitchCamera : MonoBehaviour
{
    public GameObject Player;
    public bool playerBool = true;
    public GameObject MainCamera;
    public bool cameraBool = true;
    public GameObject startPosition;
    // Start is called before the first frame update
    void Start()
    {
        
    }

    // Update is called once per frame
    void Update()
    {
        if(Input.GetKeyDown(KeyCode.V)){
            playerBool = !playerBool;
            cameraBool = !cameraBool;
            Player.SetActive(playerBool);
            MainCamera.GetComponent<CinemachineBrain>().enabled = cameraBool;
            if(!cameraBool){
                MainCamera.transform.position = startPosition.transform.position;
                MainCamera.transform.rotation = startPosition.transform.rotation;
            }
            MainCamera.GetComponent<SimpleCameraController>().enabled = !cameraBool;
        }
    }
}
