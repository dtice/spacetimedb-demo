using SpacetimeDB.Types;
using Unity.VisualScripting;
using UnityEngine;

public class CowController : EntityController
{
    public static Color[] ColorPalette = new[]
    {
        (Color)new Color32(119, 252, 173, 255),
        (Color)new Color32(76, 250, 146, 255),
        (Color)new Color32(35,  246, 120, 255),

        (Color)new Color32(119, 251, 201, 255),
        (Color)new Color32(76, 249, 184, 255),
        (Color)new Color32(35, 245, 165, 255),
    };
    public void Spawn(Cow cow)
    {
        base.Spawn(cow.EntityId);
        SetColor(ColorPalette[EntityId % ColorPalette.Length]);
    }
}
