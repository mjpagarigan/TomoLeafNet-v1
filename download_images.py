import urllib.request
import os

urls = {
    "a8cb58e0f99245a7be594e1c6e8e6077_Home_Screen.png": "https://lh3.googleusercontent.com/aida/ADBb0ug4h16BpZPFSibWOe6U0TaJUp-2-oEJDV20Hhny3jO4e0qwxmFyWBeOmT1m4DKWOJhfi2R_BssR6MbtyGEadXBBTX6uKxyycDndqPtYE5eYlDzAhfFQMBLv3loS5eVhUHkw_GaJHWdcT30gZNfy8KlrKqO0qSo8QfHLLKAU76S8M_T5WUDdb_seejUxuT94ZO3uNgnjtKF1D88zH-yGsFnkuZMCYbRpLexfx9p9OYakoJyhjlnh_hsn2Q",
    "ac46a2e498d24ca9aa177a4fb21b12ce_Home_Screen.png": "https://lh3.googleusercontent.com/aida/ADBb0uj_Exe35q9EwFAVS3NFzoi88cCtMcLQEOdqa9vrkhkCNSanc4ArXAk06zOniqhfM7MqT6A9BzuzFSRZrHDM6dR-tf7HgGAMks5Ag6113Z0utDMfYBMpHbhBt5KRwg_AgxmdYvGgcRlBkp25C4bmE7PxayoWDiPQ1Yd6BfNaRocc6wBjN-MSpAsndBmJb1giCJG4v1a0f3Rhq31Ked5NqvndeQGKs-6_3Jax2pOs7pt5mvPKSypuvnjKVw",
    "1bda7c9cfeab4f16a455cfd2bda44cac_Chat.png": "https://lh3.googleusercontent.com/aida/ADBb0uiwhyg3_1dqHmMIldBpCXvE0kEew8G2TRYDkeBT6-IKbhaGqiUOdajAEJVrDzN814EUNJPjJUw28XeTlIeBlsn1sV6HpCmS8mEZ-MJekeh_IKFKUXDm_ULlIFm8vbrb10lrMEVkNblzZI21WQng0-s3yWeFf75jJc9VR-jgHzSlwMPSqR3DSRH6l_y5Ak8it4uiVO0TyCi5HBu3pWCvKlm7M-jL7QBeD5-h-e7-evxmRwH-VIYN2ILHOvA",
    "b0b67aa69b7a45f7905eee585e5406d2_Plant_History.png": "https://lh3.googleusercontent.com/aida/ADBb0uh6AU-ohIXJH0V1l5UkODK4Bt8r4pINoAQ1Q4icq9mHtIqQ2ShsFNpuVeUu_2NvLF0MiozJQO1PFOI8ir13bn3lAlnHQXrimsY33DAGRKK_WjIFd3rcZsc794XBUqQOSnLNDYtW5ZJljl6-eq9FoUuz6uP1_m6yUMZVUPnvXqezQAPJFvctB7Ow9Q0HtoFG6J3tWzARG4epElyOlHGdVR-_nrjGKufhhJKL5wy4V01Ft8aaz_YYZw8eW5E",
    "b63a5ed8b8514689b3f091aaff931346_Plant_History.png": "https://lh3.googleusercontent.com/aida/ADBb0uiZHVlpr-7JTFeU4a0wvngRZVaChE945B8LxZqu6Gk0MbZ6czNb1bFYuLgx6UE93yHqtHC4_qNrA9L7QTwQT4Hwo34eXb0l9BOGbD99y9wQ_3NhEwIpeus_LqEJUnzDPHagN_7Nzf7Vzd_nuUFdTsucdmsTx0Af6WAi4l-1Uhdma8FOx3fW1-oW_DupF81PrjQZw-jiPnrJCoyiXfxSIlWkZN91CiDEQfbsGnP18777oA_afDnAWorsW40",
    "ba836b71ee424b2d8c9575751f6d91b1_Chat.png": "https://lh3.googleusercontent.com/aida/ADBb0ujk0BLnF8C14uJAvPIj55gUgENDddqECAoBCMc1wqr6BelQ1i7qJfEDAkLgJ_SZheI8NSYXx-tniUrLXK3vLZcls03eQUl2LOcdg8dt1tV-DbgKXLvjRjF5K2l5p69v-Mxoo-NNcgCKGYQfy-chbxoCNtGuRl6cG1EXTSAn3PGVgwu8r17pcCSqTLEuUoKtL6EYzVqPIATvvJbAVpZ6L6urv3ap8-dpG1-61HPewGyxppddrMV0VVvK7qg",
    "85cc05806d194661836ce6cef0ddcfad_Diagnosis.png": "https://lh3.googleusercontent.com/aida/ADBb0uj06iTJ5F6zhsEgBdKpVcgO5TRj__qYOP33DxFgNHAZTBdj18zN5pSudBExE_rfhLQIvilaskv-gQADdqOFVhjqdC6RCzmSGW6QsGpoG2zOphIo_iWU9V3gdBykswL5r1vWgVzYLuRGl2cCllQecmHGPRWnvkltEAYhKnkanDrV5ZU4O26k-YITkBNaRZ2BnXy197uVjN8RHdCqwU9g3mQ61fp68j3m8jatQa9219iKjors71a5o9AkiA",
    "c155a8329c8e43eca213a14f1abf97e2_Diagnosis.png": "https://lh3.googleusercontent.com/aida/ADBb0uiu6OqltPOcKF0wpaPPxD1vc_6ARcPv8ruYL03vRZQjSr1n3DgIlxLJl0_7hteJD2NVPPYr5lxwh7m8tLP14IJvBfyP900NAWTPKkEXrl4jGj2IwFpmWZkzrAHcSZFTM60eT9Mxv4tB8eBkZ_qcSUvj8AsMATDIyiMdhKokIQzkYhULtUWNnxxRbtEt-sdnJlWuQGbaG_2VopywTm3rxeJLQCrRFniZZJhxNvk883SNOSDUB5IbhZP2OTQ",
    "ea553952829d453cad5591d2c40c3500_Camera.png": "https://lh3.googleusercontent.com/aida/ADBb0ui-DRyCKyrugwUwPxMEy_ht55xKQ5HLzlCXxjPtqrQmq8Gie_gR_tTMIU3IYxZTf72lSEySul31sHmpFZK0i7yHj7pRXbS4PgBb6Q1KhVfFCRn6tKE8BTcf-4XH29lhkzCLC7cfU-kmFErLKCSVv2z_7jjL_b6FTxI8CgztQjTX_2xCrH2HAsjsEeeVsj5TFMEMTF1pIe4RxCiCwVtXO8g2zOJTgi_IXDtxd1VzKf_whDQaNBuMGfMvoPc"
}

dest_dir = r"C:/Users/iamha/.gemini/antigravity/brain/664ed3cb-1370-4e1c-9ec6-58399091f1df"

for name, url in urls.items():
    path = os.path.join(dest_dir, name)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req) as response, open(path, 'wb') as out_file:
            data = response.read()
            out_file.write(data)
        print(f"Downloaded {name}")
    except Exception as e:
        print(f"Error downloading {name}: {e}")
