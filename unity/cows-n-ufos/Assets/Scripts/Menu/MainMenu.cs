using TMPro;
using UnityEngine;
using UnityEngine.SceneManagement;
using UnityEngine.UI;

public class MainMenu : MonoBehaviour
{
    [Header("Menu Navigation")]
    [SerializeField] private GameObject mainMenuPanel;
    [SerializeField] private GameObject settingsPanel;

    [Header("Button References")]
    [SerializeField] private Button playButton;
    [SerializeField] private Button settingsButton;
    [SerializeField] private Button quitButton;
    [SerializeField] private Button backButton;
    [SerializeField] private TMP_InputField nameField;

    [Header("Game Settings")]
    [SerializeField] private string gameSceneName = "GameScene";
    
    private void Start()
    {
        // Ensure the main menu is visible and settings is hidden at start
        mainMenuPanel.SetActive(true);
        settingsPanel.SetActive(false);
        nameField.text = PlayerPrefs.GetString("PlayerName");
        if (nameField.text == "")  playButton.interactable = false;

        // Add listeners to buttons
        playButton.onClick.AddListener(PlayGame);
        settingsButton.onClick.AddListener(OpenSettings);
        quitButton.onClick.AddListener(QuitGame);
        backButton.onClick.AddListener(BackToMainMenu);
        nameField.onValueChanged.AddListener(OnTextChanged);
    }

    private void PlayGame()
    {
        Debug.Log("Starting the game!");
        SceneManager.LoadScene(gameSceneName);
    }

    private void OpenSettings()
    {
        mainMenuPanel.SetActive(false);
        settingsPanel.SetActive(true);
    }

    private void BackToMainMenu()
    {
        settingsPanel.SetActive(false);
        mainMenuPanel.SetActive(true);
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

    private void OnTextChanged(string newText)
    {
        PlayerPrefs.SetString("PlayerName", newText);
        playButton.interactable = newText != "";
    }
}