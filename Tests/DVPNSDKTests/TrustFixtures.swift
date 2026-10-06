//
//  TrustFixtures.swift
//  DVPNSDK
//

import Foundation

/// Made-up roots and leaves for the SNI route's trust check, generated once with openssl (validity 100 years; the
/// check reads no dates). Each is DER, base64-encoded.
enum TrustFixtures {
    /// The test root's public key as SubjectPublicKeyInfo DER (the form a backend hands over).
    static let testRootSPKI = Data(base64Encoded:
        "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7cgUy+MBVWB0dU2lSBBMmD1raXIkmBOdtwU3l59/3tvkE55ETXEIJwrL" +
            "nHipBDa1FdUqIRwsa0f8Iiog5FUBNqF+UAX/cmremuryOvI51G5h6apLrxc2EhHK4OYgnbL5+eO95YOwjwAgLTkxPZfYxTWOevAQ" +
            "EN0dOAbD1WcjXVR5KZF3NwVSGk+Ztn8ghyx741EsgAPVSElVrr+3cY8del98qYZhHd0wS6lW/A55KoHU7RmDEcqXkn6H/dKqM+y0" +
            "+LZxZcfMkgz1mBLm/lUwJok3eE2PtUHhb7Y8DOhjwkC8kHIFhN4A+uQQxe5bakHrJcS9wgN7anZ7mGtZMgvzjwIDAQAB")!

    /// The same key as PKCS#1 DER (the form `SecKeyCopyExternalRepresentation` returns).
    static let testRootPKCS1 = Data(base64Encoded:
        "MIIBCgKCAQEA7cgUy+MBVWB0dU2lSBBMmD1raXIkmBOdtwU3l59/3tvkE55ETXEIJwrLnHipBDa1FdUqIRwsa0f8Iiog5FUBNqF+" +
            "UAX/cmremuryOvI51G5h6apLrxc2EhHK4OYgnbL5+eO95YOwjwAgLTkxPZfYxTWOevAQEN0dOAbD1WcjXVR5KZF3NwVSGk+Ztn8g" +
            "hyx741EsgAPVSElVrr+3cY8del98qYZhHd0wS6lW/A55KoHU7RmDEcqXkn6H/dKqM+y0+LZxZcfMkgz1mBLm/lUwJok3eE2PtUHh" +
            "b7Y8DOhjwkC8kHIFhN4A+uQQxe5bakHrJcS9wgN7anZ7mGtZMgvzjwIDAQAB")!

    /// Another root's public key.
    static let otherRootPKCS1 = Data(base64Encoded:
        "MIIBCgKCAQEAtTV/7pkMecgURnDrvf3RmH5PYTFPBpY2CzjugfLbf+NWnkOpGakTJaJIxuNff0sMtXwKHMcN2ydvy14rxIiXu3EX" +
            "J/+Whv4/Cxw05/s2XNODMEMOxPc4gB/DHpcf3EbdiG44ySrgyVUQAf2LknAgBUaieio/zgPdq2G43gnaB0A1exxE3HjIKaYjK51L" +
            "N/7OFqZ6DIFTkmcOCF7ihkADyfgxY0iCI2V14VlDuJNh8tg6a0goGEHI9KjnY67IwmjJ2qlS77dk9YbPP1E+zJOhQh6+vHV4DOnl" +
            "BbXf3j6kQuTtXc6WHCCKhwN7/TYZpDWiu3rwAE8huiD3b0FGPiUS2QIDAQAB")!

    /// A 3072-bit root's public key.
    static let bigRootSPKI = Data(base64Encoded:
        "MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2fEYsZMDnYqO4J3Q/YSShu0qZwzmW1YSHhiF96E/YXhrF7lYkZRKkz5x" +
            "BU3X5UO7IE/ujBnwykUzUlJ31zs0olQAO0Wb/6bsZKeH9BDVlS5+GKXCCHd49WSLI5iNJsg6Kkk9PiRrICVHSIil3KagmFw3igtB" +
            "XY8jl+oUWaiD9NO3WDviGBo7vEyfVsjXhaMvT1mE7uYIPx9IbYRq8c6k6sOHPGGN2xx1m3l+GfdH0iXZTYzcUxCtUXwJT+Wn0RnI" +
            "CgdileMF5JDxul32dUN9BK9TGqh+ghqv08YN+bLRrgcvrBElEkzuG05tf0xIk+fhXR1n6vp/1sZNLvKndmoMDSLebkUOlWUvHvX7" +
            "SFzvqIKDkWmwTKp14ruOoREtExKYnq37dWhEu/5bQnsNSNawdiN18gTL5dYSy6BIFXT4N4KR0BsAdo89oN3fCEJKN/uyI0vTld+E" +
            "mw7Wxy8uw4oF4shRrqa69OP9XY+vWkQ6pAq1BSh+B+uyCo/BhsgjpFyTAgMBAAE=")!

    /// An X.509 v1 leaf for `mirror.test`, without extensions, signed by the test root: what a mirror presents.
    static let mirrorLeaf = Data(base64Encoded:
        "MIICqDCCAZACCQC/SR21Qb6myDANBgkqhkiG9w0BAQsFADAUMRIwEAYDVQQDDAl0ZXN0LXJvb3QwIBcNMjYxMDA1MTExNDE1WhgP" +
            "MjEyNjA5MTExMTE0MTVaMBYxFDASBgNVBAMMC21pcnJvci50ZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA7WUk" +
            "khHtASuIjqKQh+EPMw+RWuhg73ThdNBxTjlcp81D7nEGPeYd9bV84RdocrKzoInb+TGMy0r7DAWDqKFOC74wXWvGYkJaQYC4f/Ct" +
            "rOYsox3ResCNb8UmTf01UFyckC0qD2kyuesldzfk07rNuK+8Z9f5n0q+K2jTouv8+KVlFh4j8kFWxdfnksKQTuixXBJEMsl4CkjZ" +
            "WulbJG/MvHQVZ7wgYXZFMrQtd2dKrFin4rjHaJfgcv2NRnrCV7DoGdfPhv0fYsbPs98E7+9NORuF2OPFiBofCvNzjHgTRZjgObKX" +
            "WF1e0WBaIKmG8SRN/1cap4Nc57vP3mGFvSpW7wIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAKS4vA8MePU59QwF2JmGYxbMQEBXuK" +
            "N1Pav9SiZatrAl8ngoURKu2bm9S1XuXFzd6v+U/M36uZGnmYZtHeyia0CarmqCYZW/6iQB0SK0v3UeIEx+5mTjUIYhlaM+IQ+LBO" +
            "5QNIovmwpEKIoxwq4avQ6hqzPAc3FjtUaPbIFQWV6n9hPOtt325Vf0yRzxKInFSIRnrZJDxE2P/shGmaIm21zGXvSh1QkuMFxyaD" +
            "wGGyUNxm/Nbqn57SOom/DqE2u3JYmDGclUC4mIjVQs2V9nF0uYBE8GYhXMLS/NOpVxJ9ZFamKytQBUU+3HWKumVtaVq9BAG3wDfE" +
            "Ip759ekHwRbN")!

    /// A leaf signed by the other root.
    static let otherLeaf = Data(base64Encoded:
        "MIICqDCCAZACCQDtBmj1Wz+/jjANBgkqhkiG9w0BAQsFADAVMRMwEQYDVQQDDApvdGhlci1yb290MCAXDTI2MTAwNTExMTQxNVoY" +
            "DzIxMjYwOTExMTExNDE1WjAVMRMwEQYDVQQDDApvdGhlci50ZXN0MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAuoAf" +
            "6MZmil0+Gd2WyFfmHEqdrXON0x63dtNg090SHVzZwtBE+zbl4A/gqKj6aIbkMPG9DfaTJD9JzijLTijIoZxJy80ds9kkX12wzJlZ" +
            "LuvCPaHweTCuj1LloDgWtq2QxrMPHgZG2OZPcmPFpEjGGWVL0sCQ1/dfK84CYzUAPRyw0Scxs5zmrx0ToPaMTtXStTbQ98yBZ4Qk" +
            "pI20mPqWre+0O2MTFTHuek/Jo2sVIDSTcgrV1W3rVD0Nc4AHkzw7irIozz4lUzLjLY19rG7em7Z5H4bGCjSTunt5Mb49m6djpors" +
            "37SfeQdZQyEtoOeoeYBWGBzYVFWnxULlopWcdQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQCSusNLGn941FxmM1C9kc7WuaH0aQG1" +
            "8u8dO2Y2CDLP6EsL64WB+iEwlfrIzUOXwRdAtG5b34j/2V1Y7M0nx7AyKloDRxlTfYmz744yUStKEJ3iCjPaQrXy3htuNjZMLpbn" +
            "eTowYuwW1HsLmn3KqObWCCFedfdyEQ7UsbqGU3udYJ/NmZyD0RelSJ8hsZVr8sHtFbaSMawDFb85Vx60jyyZTqG3bzSUzJ+Senb9" +
            "/+Ytk9rDvaT/iWANwGaJenvb5hUW6SCUwxIJB6NcjPjRFzlLTq+qLYzbGRCWwUVLk/xAzuLeVcEmCOC3CSDSRuVWMSCtx8oYgIH7" +
            "rqpXZYn7vI+3")!

    /// A leaf signed by the 3072-bit root.
    static let bigLeaf = Data(base64Encoded:
        "MIIDJDCCAYwCCQC+osZCa/fakjANBgkqhkiG9w0BAQsFADATMREwDwYDVQQDDAhiaWctcm9vdDAgFw0yNjEwMDUxMTE0MTZaGA8y" +
            "MTI2MDkxMTExMTQxNlowEzERMA8GA1UEAwwIYmlnLnRlc3QwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQCff1CwH2fZ" +
            "FDlKnkbZdLfFHrpZ6tI0kXtPAMRMASyJN2GcIHbaHf41cph2QYX4BnU/q7kD++Y1/O9gh5bNxkeJNTqtZe+JaeHBL16N4VVmSG3F" +
            "Qq7W7OkVgsQUFVkQd+a21HKy2wUTFjo/ZG6NzaxcCNEaZ///totcy+50ghpeJA+oGoBsLZz3yW/+fMw4yd6OOlCBXQhVHy6PkGXE" +
            "JzaxDDCYaxDp/NaTcNkUJdhKvnxQwAZJiDL3WvYStXBtYwmogzKo3kdlfAF/xgXX6JNIMO98Y1bwuxcWR/I8CR3h97P5loIMnaIA" +
            "+smBZWKv4Xw+8mTAhcdcZ2MnQXCkG0fxAgMBAAEwDQYJKoZIhvcNAQELBQADggGBAGgZYv1zmMgZ+wS4d2TKhB4RzWiWYSeHvKpT" +
            "Fi1iSAwiU0PRiEdicFg3RxfxknuXQcj0BGEp+rL2+ATf7pAMfLGRpxvA8K7+iMzSc0d47u2QLl5TgwVOKZQKPUUSxCmSd2R0ZVPo" +
            "TSIotK/G/0OI+0jow+gmwsiBHsfXyQAQh1QhpcAGjOGwVrMLSmmWW5ky9RRlPzzI6GgYrBcUhARE/wzVjRo9hgQOUpAHqRphQ2Cr" +
            "iUDz9a9pitFmIJieZ1AesfZrXW8g8yKg3OQi3MHmbrlixS/NYYQydoVEJIDK1qX0/EIQJGbTHtlktVXRyUC1mGDtQZQOXyaU1tL1" +
            "NDbdA7Hyawp+D6bEuqslyqfbX4EWWQrv2DR+ryu6mZuJ2NcSHpzuHqjMcF+GpKql+T2ximmRPXEOcGCCgN6fCimRuiWvJJnWxQjc" +
            "71ljKuDkiAifQWGtLv9uPjHEQqzup6behKOu2KqjAdruv+0ZRIk9brQkqC7XQo7OAS+WX1PY4jl2cg==")!
}
