import Foundation

/// Quita el rastreo de los enlaces que copias.
///
/// Compartes un enlace y va cargado: de dónde salió, en qué campaña, qué correo lo
/// abrió, a veces hasta quién eres. `?utm_source=…`, `fbclid`, `si=` de Spotify. Esto
/// lo deja en el enlace de verdad.
///
/// La regla que manda aquí es **no romper nada**. Un limpiador demasiado listo que
/// se cargue un parámetro necesario es mucho peor que uno que deje pasar rastreo:
/// por eso se quita solo lo que está en la lista, nunca lo que no se reconoce, y hay
/// excepciones por sitio para los casos que se parecen pero no lo son.
enum URLCleaner {

    /// Parámetros de rastreo que sobran en cualquier sitio.
    static let junk: Set<String> = [
        // Campañas
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "utm_name", "utm_reader", "utm_social", "utm_brand",
        // Redes y anuncios
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid", "twclid", "ttclid",
        "igshid", "igsh", "yclid", "wbraid", "gbraid", "vero_id", "vero_conv",
        // Correo
        "mc_cid", "mc_eid", "mkt_tok", "_hsenc", "_hsmi", "hsCtaTracking",
        // Analítica
        "_ga", "_gl", "oly_anon_id", "oly_enc_id", "cmpid", "trk", "trkCampaign",
        "sc_campaign", "sc_channel", "sc_content", "sc_medium", "sc_outcome",
    ]

    /// Parámetros que solo son rastreo **en ciertos sitios**.
    ///
    /// `si` es el identificador de quien comparte en Spotify y YouTube, pero en otros
    /// sitios puede significar cualquier cosa. `s` y `t` igual: en X sobran, y en un
    /// buscador cualquiera podrían ser la búsqueda o la pestaña. Fuera de estos
    /// dominios no se tocan.
    static let byHost: [String: Set<String>] = [
        "open.spotify.com": ["si", "nd", "_branch_match_id", "context"],
        "spotify.link": ["si"],
        "youtube.com": ["si", "pp", "feature"],
        "youtu.be": ["si", "feature"],
        "music.youtube.com": ["si", "feature"],
        "x.com": ["s", "t", "ref_src", "ref_url"],
        "twitter.com": ["s", "t", "ref_src", "ref_url"],
        "amazon.com": ["ref", "ref_", "pd_rd_i", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pf_rd_i",
                       "pf_rd_m", "pf_rd_p", "pf_rd_r", "pf_rd_s", "pf_rd_t", "th", "psc"],
        "amazon.es": ["ref", "ref_", "pd_rd_i", "pd_rd_r", "pd_rd_w", "pd_rd_wg", "pf_rd_i",
                      "pf_rd_m", "pf_rd_p", "pf_rd_r", "pf_rd_s", "pf_rd_t", "th", "psc"],
        "instagram.com": ["igshid", "igsh", "img_index"],
        "tiktok.com": ["is_from_webapp", "sender_device", "web_id"],
        "aliexpress.com": ["spm", "scm", "pdp_ext_f", "algo_pvid", "algo_exp_id"],
        "ebay.com": ["hash", "mkevt", "mkcid", "mkrid", "campid", "toolid"],
        "linkedin.com": ["trk", "trackingId", "originalSubdomain", "lipi"],
        "reddit.com": ["share_id", "utm_name", "rdt"],
    ]

    /// Devuelve el enlace limpio, o `nil` si no había nada que quitar.
    ///
    /// Solo actúa si el texto **entero** es una dirección http(s). Un párrafo con un
    /// enlace dentro se deja en paz: reescribir texto ajeno da más sustos que
    /// alegrías.
    static func clean(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              let items = components.queryItems, !items.isEmpty else { return nil }

        let extra = hostRules(for: host)
        let kept = items.filter { !junk.contains($0.name) && !extra.contains($0.name) }
        guard kept.count != items.count else { return nil }

        var cleaned = components
        cleaned.queryItems = kept.isEmpty ? nil : kept
        guard let result = cleaned.string, result != trimmed else { return nil }
        return result
    }

    /// Las reglas de un dominio, subdominios incluidos: `www.amazon.es` usa las de
    /// `amazon.es`.
    static func hostRules(for host: String) -> Set<String> {
        if let exact = byHost[host] { return exact }
        for (domain, rules) in byHost where host.hasSuffix("." + domain) { return rules }
        return []
    }
}
