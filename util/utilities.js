module.exports = {
    fromDecimalsToCurrency(decimals) {
        var symbols = {
            "noether": "0",
            "wei": "1",
            "kwei": "1000",
            "Kwei": "1000",
            "babbage": "1000",
            "femtoether": "1000",
            "mwei": "1000000",
            "Mwei": "1000000",
            "lovelace": "1000000",
            "picoether": "1000000",
            "gwei": "1000000000",
            "Gwei": "1000000000",
            "shannon": "1000000000",
            "nanoether": "1000000000",
            "nano": "1000000000",
            "szabo": "1000000000000",
            "microether": "1000000000000",
            "micro": "1000000000000",
            "finney": "1000000000000000",
            "milliether": "1000000000000000",
            "milli": "1000000000000000",
            "ether": "1000000000000000000",
            "kether": "1000000000000000000000",
            "grand": "1000000000000000000000",
            "mether": "1000000000000000000000000",
            "gether": "1000000000000000000000000000",
            "tether": "1000000000000000000000000000000"
        };
        var d = "1" + (new Array(decimals instanceof Number ? decimals : parseInt(decimals) + 1)).join('0');
        var values = Object.entries(symbols);
        for (var i in values) {
            var symbol = values[i];
            if (symbol[1] === d) {
                return symbol[0];
            }
        }
    }
}