using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

public class GameMenu : MonoBehaviour
{
    [Header("Menu Navigation")]
    [SerializeField] private GameObject mainMenuPanel;
    [SerializeField] private GameObject settingsPanel;

    [Header("Button References")]
    [SerializeField] private Button resumeButton;
    [SerializeField] private Button settingsButton;
    [SerializeField] private Button menuButton;
    [SerializeField] private Button quitButton;
    [SerializeField] private Button backButton;

    [Header("Game Settings")]
    [SerializeField] private string menuScene = "MenuScene";
    
    private void Start()
    {
        // Ensure the main menu is visible and settings is hidden at start
        mainMenuPanel.SetActive(true);
        settingsPanel.SetActive(false);
        
        // Add listeners to buttons
        resumeButton.onClick.AddListener(Resume);
        settingsButton.onClick.AddListener(OpenSettings);
        quitButton.onClick.AddListener(QuitGame);
        menuButton.onClick.AddListener(QuitToMenu);
        backButton.onClick.AddListener(BackToMain);
    }

    private void Update()
    {
        if (Input.GetKeyDown(KeyCode.Escape))
        {
            Debug.Log("Escape Menu");
            if (settingsPanel.activeSelf)
            {
                BackToMain();
            }
            else
            {
                GameManager.Instance.ToggleMenu();
            }
        }
    }

    private void Resume()
    {
        GameManager.Instance.ToggleMenu();
    }

    private void OpenSettings()
    {
        mainMenuPanel.SetActive(false);
        settingsPanel.SetActive(true);
    }

    public void BackToMain()
    {
        settingsPanel.SetActive(false);
        mainMenuPanel.SetActive(true);
    }

    private void QuitToMenu()
    {
        SceneManager.LoadScene(menuScene);
        GameManager.Instance.Disconnect();
    }

    private void QuitGame()
    {
        Debug.Log("Quitting the game!");
        
#if UNITY_EDITOR
        UnityEditor.EditorApplication.isPlaying = false;
#else
                Application.Quit();
#endif
    }
}
